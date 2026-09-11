HumaLike = HumaLike or {}

local license = GetConvar('humalike_license_key', '')
local bootId = nil
local generation = 0
local bootstrapInFlight = false
local bootstrapScheduled = false
local stopping = false
local invalidatedAssignment = nil
local runtimeActivated = false

local function stopFailedStartup(detail)
    if runtimeActivated or stopping or type(StopResource) ~= 'function' then return false end
    stopping = true
    generation = generation + 1
    HumaLike.ClearRuntimeCredentials()
    HumaLike.SetStatus('stopped', detail)
    StopResource(GetCurrentResourceName())
    return true
end

local function invalidateRuntime()
    local current = HumaLike.RuntimeCredentials()
    if current then
        invalidatedAssignment = {
            edgeUrl = current.edgeUrl,
            edgeAssignmentId = current.edgeAssignmentId,
            edgeNodeId = current.edgeNodeId,
            edgeBootId = current.edgeBootId,
            edgeGeneration = current.edgeGeneration,
            voiceUrl = current.voiceUrl,
            voiceAssignmentId = current.voiceAssignmentId,
            voiceNodeId = current.voiceNodeId,
            voiceBootId = current.voiceBootId,
            voiceGeneration = current.voiceGeneration,
        }
    end
    generation = generation + 1
    HumaLike.ClearRuntimeCredentials()
end

HumaLike.InvalidateRuntimeCredentials = invalidateRuntime

local function assignmentRejected(status, payload)
    if status ~= 409 then return false end
    local code = HumaLike.ErrorCode(payload)
    return code == 'EDGE_ASSIGNMENT_NOT_READY'
        or code == 'VOICE_ASSIGNMENT_NOT_READY'
        or code == 'EDGE_WRONG_OWNER'
        or code == 'EDGE_ASSIGNMENT_STALE'
end

local function sameEdgeAssignment(left, right)
    return left and right
        and left.edgeUrl == right.edgeUrl
        and left.edgeAssignmentId == right.edgeAssignmentId
        and left.edgeNodeId == right.edgeNodeId
        and left.edgeBootId == right.edgeBootId
        and left.edgeGeneration == right.edgeGeneration
end

local function sameVoiceAssignment(left, right)
    return left and right
        and left.voiceUrl == right.voiceUrl
        and left.voiceAssignmentId == right.voiceAssignmentId
        and left.voiceNodeId == right.voiceNodeId
        and left.voiceBootId == right.voiceBootId
        and left.voiceGeneration == right.voiceGeneration
end

local function announceAssignment(plane, credentials, reason)
    local nodeId = credentials[plane .. 'NodeId']
    local assignmentGeneration = credentials[plane .. 'Generation']
    local url = credentials[plane .. 'Url']
    print(('[humalike] runtime_assignment_changed plane=%s node_id=%s generation=%s url=%s reason=%s')
        :format(plane, nodeId, assignmentGeneration, url, reason))
    TriggerEvent(('humalike:runtime:%sChanged'):format(plane), {
        nodeId = nodeId,
        generation = assignmentGeneration,
        url = url,
        reason = reason,
    })
end

local function announceInitialRuntime(reason)
    HumaLike.SetStatus('ready', reason)
    TriggerEvent('humalike:core:ready', {
        generation = generation,
        reason = reason,
    })
end

local function uuid4()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return template:gsub('[xy]', function(character)
        local value = math.random(0, 15)
        if character == 'y' then value = (value % 4) + 8 end
        return ('%x'):format(value)
    end)
end

local function installRuntime(payload, reason)
    local previous = HumaLike.RuntimeCredentials() or invalidatedAssignment
    local ok, validationError = HumaLike.ReplaceRuntimeCredentials(payload, bootId)
    if not ok then return false, validationError end
    local current = HumaLike.RuntimeCredentials()
    invalidatedAssignment = nil
    runtimeActivated = true
    generation = generation + 1
    bootstrapInFlight = false
    bootstrapScheduled = false
    if not previous then
        announceInitialRuntime(reason)
    else
        if not sameEdgeAssignment(previous, current) then
            announceAssignment('edge', current, reason)
        end
        if not sameVoiceAssignment(previous, current) then
            announceAssignment('voice', current, reason)
        end
        HumaLike.SetStatus('ready', reason)
        TriggerEvent('humalike:runtime:refreshed', { reason = reason })
    end
    return true
end

local function scheduleRenewal(expectedGeneration, attempt)
    local delay = attempt == 1 and HumaLike.RenewalDelay()
        or HumaLike.RetryDelay(attempt - 1)
    SetTimeout(delay, function()
        if stopping or generation ~= expectedGeneration then return end
        local credentials = HumaLike.RuntimeCredentials()
        if not credentials then
            HumaLike.RequestBootstrap('runtime credentials missing', 1, true)
            return
        end
        HumaLike.EdgeRequest('renew_fivem_runtime', credentials.edgeToken, {
            boot_id = bootId
        }, function(status, payload)
            if stopping or generation ~= expectedGeneration then return end
            if status == 200 then
                local previous = HumaLike.RuntimeCredentials()
                local ok = HumaLike.ReplaceRuntimeCredentials(payload, bootId)
                if ok then
                    local current = HumaLike.RuntimeCredentials()
                    local edgeChanged = not sameEdgeAssignment(previous, current)
                    local voiceChanged = not sameVoiceAssignment(previous, current)
                    if edgeChanged or voiceChanged then
                        generation = generation + 1
                        if edgeChanged then
                            announceAssignment('edge', current, 'assignment changed during renewal')
                        end
                        if voiceChanged then
                            announceAssignment('voice', current, 'assignment changed during renewal')
                        end
                        HumaLike.SetStatus('ready', 'runtime assignment changed during renewal')
                        scheduleRenewal(generation, 1)
                    else
                        HumaLike.SetStatus('ready', 'runtime credentials renewed')
                        scheduleRenewal(expectedGeneration, 1)
                    end
                    return
                end
                invalidateRuntime()
                HumaLike.SetStatus('bootstrapping',
                    'renewal returned malformed credentials')
                HumaLike.RequestBootstrap('renewal credentials malformed', 1, true)
                return
            elseif status == 401 or status == 403
                or assignmentRejected(status, payload) then
                invalidateRuntime()
                HumaLike.SetStatus('bootstrapping',
                    'runtime assignment rejected; bootstrapping')
                HumaLike.RequestBootstrap('renewal assignment rejected', 1, true)
                return
            else
                HumaLike.SetStatus('degraded',
                    ('renewal failed with HTTP %s'):format(status))
            end
            scheduleRenewal(expectedGeneration, attempt + 1)
        end)
    end)
end

function HumaLike.RequestBootstrap(reason, attempt, immediate)
    if stopping or bootstrapInFlight or bootstrapScheduled then return false end
    if license == '' then
        HumaLike.SetStatus('stopped',
            'missing server-only convar humalike_license_key')
        return false
    end

    attempt = math.max(tonumber(attempt) or 1, 1)
    bootstrapScheduled = true
    SetTimeout(immediate and 0 or HumaLike.RetryDelay(attempt), function()
        bootstrapScheduled = false
        if stopping or bootstrapInFlight then return end
        bootstrapInFlight = true
        HumaLike.SetStatus('bootstrapping', ('%s; request attempt %d'):format(
            reason or 'bootstrap requested', attempt))
        HumaLike.EdgeRequest('bootstrap_fivem_runtime', license, {
            boot_id = bootId,
            previous_lease_id = HumaLike.PreviousRuntimeLeaseId()
        }, function(status, payload)
            bootstrapInFlight = false
            if stopping then return end
            if status == 200 then
                local ok, validationError = installRuntime(
                    payload, 'runtime credentials installed')
                if ok then
                    scheduleRenewal(generation, 1)
                    return
                end
                invalidateRuntime()
                if stopFailedStartup('control-plane credentials failed startup gate') then
                    return
                end
                HumaLike.SetStatus('degraded', validationError)
            elseif status == 401 or status == 403 then
                invalidateRuntime()
                if HumaLike.ErrorCode(payload) ~= 'RUNTIME_LEASE_UNKNOWN' then
                    HumaLike.SetStatus('unauthorized', 'license rejected by control plane')
                    return
                end
                HumaLike.SetStatus('degraded', 'control-plane runtime state unavailable')
            elseif assignmentRejected(status, payload) then
                invalidateRuntime()
                HumaLike.SetStatus('degraded', 'runtime assignment is not ready')
            else
                local errorCode = HumaLike.ErrorCode(payload)
                HumaLike.SetStatus('degraded',
                    ('bootstrap failed with HTTP %s code=%s'):format(
                        status, errorCode or 'unknown'))
            end
            HumaLike.RequestBootstrap(reason, attempt + 1, false)
        end)
    end)
    return true
end
function HumaLike.Bootstrap(attempt)
    return HumaLike.RequestBootstrap('bootstrap requested', attempt or 1, true)
end

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    math.randomseed(os.time() + GetGameTimer())
    bootId = uuid4()
    HumaLike.RequestBootstrap('resource started', 1, true)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopping = true
    TriggerEvent('humalike:core:stopping')
    generation = generation + 1
    invalidatedAssignment = nil
    HumaLike.ClearRuntimeCredentials()
end)
