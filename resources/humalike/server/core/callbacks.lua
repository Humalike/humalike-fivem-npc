HumaLike = HumaLike or {}

local handlers = {}
local completed = {}
local completionOrder = {}
local maxCompleted = 1024

local function constantTimeEquals(left, right)
    if type(left) ~= 'string' or type(right) ~= 'string' or #left ~= #right then
        return false
    end
    local difference = 0
    for index = 1, #left do
        difference = difference | (string.byte(left, index) ~ string.byte(right, index))
    end
    return difference == 0
end

local function callbackAuthorized(authorization)
    local runtime = HumaLike.RuntimeCredentials()
    if not runtime then return false end
    local now = os.time()
    for _, credential in ipairs({ runtime.callbackCurrent, runtime.callbackNext }) do
        if now >= credential.valid_from_unix and now < credential.valid_until_unix
            and constantTimeEquals(authorization, 'Bearer ' .. credential.token) then
            return true
        end
    end
    return false
end

local function remember(requestId, status, body)
    completed[requestId] = { status = status, body = body }
    completionOrder[#completionOrder + 1] = requestId
    if #completionOrder > maxCompleted then
        local oldest = table.remove(completionOrder, 1)
        completed[oldest] = nil
    end
end

local function sendJson(response, status, body)
    response.writeHead(status, { ['Content-Type'] = 'application/json' })
    response.send(json.encode(body))
end

function HumaLike.RegisterCallback(path, handler)
    assert(type(path) == 'string' and path:sub(1, 1) == '/', 'callback path must be absolute')
    assert(type(handler) == 'function', 'callback handler must be a function')
    assert(handlers[path] == nil, ('duplicate callback path %s'):format(path))
    handlers[path] = handler
end

SetHttpHandler(function(request, response)
    local handler = handlers[request.path]
    if request.method ~= 'POST' or not handler then
        response.writeHead(404)
        response.send()
        return
    end

    local authorization = request.headers['authorization'] or request.headers['Authorization'] or ''
    if not callbackAuthorized(authorization) then
        response.writeHead(401)
        response.send()
        return
    end

    request.setDataHandler(function(rawBody)
        if not callbackAuthorized(authorization) then
            response.writeHead(401)
            response.send()
            return
        end
        local decoded, payload = pcall(json.decode, rawBody or '')
        if not decoded or type(payload) ~= 'table' or type(payload.request_id) ~= 'string'
            or payload.request_id == '' then
            sendJson(response, 400, { ok = false, error = 'invalid_request' })
            return
        end

        local previous = completed[payload.request_id]
        if previous then
            sendJson(response, previous.status, previous.body)
            return
        end

        local ok, status, body = pcall(handler, payload)
        if not ok then
            print(('[humalike] callback %s failed: %s'):format(request.path, status))
            sendJson(response, 500, { ok = false, error = 'handler_failed' })
            return
        end
        status = type(status) == 'number' and status or 200
        body = type(body) == 'table' and body or { ok = true }
        remember(payload.request_id, status, body)
        sendJson(response, status, body)
    end)
end)
