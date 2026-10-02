HumaLike = HumaLike or {}

-- The public release targets production. Environment-specific release jobs
-- replace this server-only constant; customers never configure service URLs.
local controlPlaneUrl = GetConvar(
    'humalike_control_plane_url', 'https://api.humalike.com')
local rejectedVoiceToken = nil
local rejectedVoiceAssignment = nil
local voiceRetryAfter = 0
local voiceRetryCooldownSeconds = 30

-- Server-side requests run through the resource's Node runtime
-- (server/core/http_node.js). PerformHttpRequest is kept only as a fallback
-- when that runtime is unavailable.
local nodeHttpExport = 'humalikeNodeHttpRequest'
local nodeHttpTimeoutMs = 35000
local pendingHttp = {}
local nextHttpId = 0
local nodeHttpFallbackLogged = false

local function resolveHttp(id, status, body, headers, errorData)
    local callback = pendingHttp[id]
    if not callback then return end
    pendingHttp[id] = nil
    callback(status, body, headers, errorData)
end

local function nodeHttpRequest(id, url, method, body, headers)
    if exports == nil or GetCurrentResourceName == nil then return false end
    return pcall(function()
        local resource = exports[GetCurrentResourceName()]
        resource[nodeHttpExport](resource, id, url, method,
            body, headers, function(status, responseBody, responseHeaders, errorData)
                -- Run like a PerformHttpRequest callback: on a Lua thread, so
                -- callers may Wait and errors stay out of the Node runtime.
                CreateThread(function()
                    resolveHttp(id, tonumber(status) or 0, responseBody,
                        responseHeaders or {}, errorData)
                end)
            end)
    end)
end

local function httpRequest(url, callback, method, body, headers)
    nextHttpId = nextHttpId + 1
    local id = ('humalike-http-%d'):format(nextHttpId)
    pendingHttp[id] = callback
    if nodeHttpRequest(id, url, method, body, headers) then
        SetTimeout(nodeHttpTimeoutMs, function()
            resolveHttp(id, 0, nil, {}, 'request timed out')
        end)
        return
    end
    pendingHttp[id] = nil
    if not nodeHttpFallbackLogged then
        nodeHttpFallbackLogged = true
        print('[humalike] node_http_unavailable; using PerformHttpRequest')
    end
    PerformHttpRequest(url, callback, method, body, headers)
end

local function encodeObject(payload)
    payload = payload or {}
    -- FiveM encodes an empty Lua table as []; edge expects {}.
    if type(payload) == 'table' and next(payload) == nil then
        return '{}'
    end
    return json.encode(payload)
end

function HumaLike.EdgeRequest(action, token, payload, callback, targetUrl)
    local edgeBaseUrl = targetUrl or controlPlaneUrl
    httpRequest(
        ('%s/v1/npc/actions/%s'):format(edgeBaseUrl, action),
        function(status, body, headers, errorData)
            local decoded = nil
            if type(body) == 'string' and body ~= '' then
                local ok, result = pcall(json.decode, body)
                if ok then decoded = result end
            end
            callback(status, decoded, headers, errorData)
        end,
        'POST',
        encodeObject(payload),
        {
            ['Authorization'] = 'Bearer ' .. token,
            ['Content-Type'] = 'application/json'
        }
    )
end

function HumaLike.ErrorCode(body)
    if type(body) ~= 'table' then return nil end
    if type(body.error) == 'table' and type(body.error.code) == 'string' then
        return body.error.code
    end
    return type(body.error_code) == 'string' and body.error_code or nil
end

function HumaLike.IsRuntimeIdentityError(status, body)
    if status ~= 401 and status ~= 403 then return false end
    local code = HumaLike.ErrorCode(body)
    return code == 'UNAUTHORIZED'
        or code == 'RUNTIME_LEASE_UNKNOWN'
        or code == 'RUNTIME_TOKEN_INVALID'
        or code == 'RUNTIME_TOKEN_EXPIRED'
end

function HumaLike.IsEdgeAssignmentError(status, body)
    if status ~= 409 then return false end
    local code = HumaLike.ErrorCode(body)
    return code == 'EDGE_ASSIGNMENT_NOT_READY'
        or code == 'EDGE_WRONG_OWNER'
        or code == 'EDGE_ASSIGNMENT_STALE'
end

function HumaLike.IsVoiceAssignmentError(status, body)
    if status ~= 409 then return false end
    local code = HumaLike.ErrorCode(body)
    return code == 'assignment_not_ready' or code == 'assignment_stale'
end

function HumaLike.PostEdgeAction(action, payload, callback)
    local credentials = HumaLike.RuntimeCredentials()
    if not credentials then
        if callback then callback(false, 0, nil) end
        return
    end
    local requestToken = credentials.edgeToken
    local requestUrl = credentials.edgeUrl
    local requestAssignment = HumaLike.EdgeAssignmentKey and HumaLike.EdgeAssignmentKey()
    HumaLike.EdgeRequest(action, requestToken, payload or {}, function(status, body)
        if requestAssignment and not HumaLike.IsCurrentEdgeAssignment(requestAssignment) then
            if callback then
                callback(false, 409, { error = { code = 'EDGE_ASSIGNMENT_CHANGED' } })
            end
            return
        end
        if HumaLike.IsRuntimeIdentityError(status, body)
            or HumaLike.IsEdgeAssignmentError(status, body) then
            local current = HumaLike.RuntimeCredentials()
            -- A response for an older request may arrive after a successful
            -- bootstrap. Never let that stale 401/403 erase the replacement
            -- credentials and start an unbounded bootstrap/reconcile loop.
            if current and current.edgeToken == requestToken
                and current.edgeUrl == requestUrl then
                local code = HumaLike.ErrorCode(body) or ('HTTP_%s'):format(status)
                HumaLike.InvalidateRuntimeCredentials()
                HumaLike.SetStatus('bootstrapping',
                    ('edge runtime rejected code=%s; refreshing assignment'):format(code))
                print(('[humalike] edge_assignment_refresh code=%s url=%s action=%s')
                    :format(code, requestUrl, action))
                HumaLike.RequestBootstrap('edge assignment rejected', 1, true)
            end
        end
        if callback then callback(status >= 200 and status < 300, status, body) end
    end, requestUrl)
end

function HumaLike.PostVoice(path, payload, callback)
    local credentials = HumaLike.RuntimeCredentials()
    if not credentials then
        if callback then callback(0, nil) end
        return
    end
    local requestToken = credentials.voiceToken
    local requestUrl = credentials.voiceUrl
    local requestAssignment = HumaLike.VoiceAssignmentKey()
    local now = os.time()
    if rejectedVoiceToken == requestToken
        and rejectedVoiceAssignment == requestAssignment
        and now < voiceRetryAfter then
        if callback then callback(401, nil) end
        return
    end
    httpRequest(requestUrl .. path, function(status, body)
        local decoded = nil
        if type(body) == 'string' and body ~= '' then
            local ok, result = pcall(json.decode, body)
            if ok then decoded = result end
        end
        if not HumaLike.IsCurrentVoiceAssignment(requestAssignment) then
            return
        end
        if status == 401 or status == 403 or HumaLike.IsVoiceAssignmentError(status, decoded) then
            local current = HumaLike.RuntimeCredentials()
            -- Voice rejection must not invalidate healthy edge credentials.
            if current and current.voiceToken == requestToken then
                if rejectedVoiceToken ~= requestToken then
                    HumaLike.SetStatus('degraded', 'voice runtime rejected; edge runtime retained')
                end
                rejectedVoiceToken = requestToken
                rejectedVoiceAssignment = requestAssignment
                voiceRetryAfter = os.time() + voiceRetryCooldownSeconds
                if HumaLike.IsVoiceAssignmentError(status, decoded) then
                    HumaLike.RequestBootstrap('voice assignment rejected', 1, true)
                end
            end
        elseif status >= 200 and status < 300
            and rejectedVoiceToken == requestToken
            and rejectedVoiceAssignment == requestAssignment then
            rejectedVoiceToken = nil
            rejectedVoiceAssignment = nil
            voiceRetryAfter = 0
        end
        if callback then callback(status, decoded) end
    end, 'POST', encodeObject(payload), {
        ['Authorization'] = 'Bearer ' .. requestToken,
        ['Content-Type'] = 'application/json'
    })
end
