HumaLike = HumaLike or {}

local license = GetConvar('humalike_license_key', '')
local bootId = nil
local generation = 0
local bootstrapInFlight = false
local bootstrapScheduled = false
local stopping = false

local function uuid4()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return template:gsub('[xy]', function(character)
        local value = math.random(0, 15)
        if character == 'y' then value = (value % 4) + 8 end
        return ('%x'):format(value)
    end)
end

local function installRuntime(payload, reason)
    local ok, validationError = HumaLike.ReplaceRuntimeCredentials(payload, bootId)
    if not ok then return false, validationError end
    generation = generation + 1
    bootstrapInFlight = false
    bootstrapScheduled = false
    HumaLike.SetStatus('ready', reason)
    TriggerEvent('humalike:core:ready', {
        generation = generation,
        reason = reason,
    })
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
                local ok, validationError = HumaLike.ReplaceRuntimeCredentials(payload, bootId)
                if ok then
                    HumaLike.SetStatus('ready', 'runtime credentials renewed')
                    scheduleRenewal(expectedGeneration, 1)
                    return
                end
                HumaLike.SetStatus('degraded', validationError)
            elseif status == 401 or status == 403 then
                HumaLike.ClearRuntimeCredentials()
                HumaLike.SetStatus('bootstrapping',
                    'runtime identity rejected; bootstrapping')
                HumaLike.RequestBootstrap('renewal identity rejected', 1, true)
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
            boot_id = bootId
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
                HumaLike.SetStatus('degraded', validationError)
            elseif status == 401 or status == 403 then
                if HumaLike.ErrorCode(payload) ~= 'RUNTIME_LEASE_UNKNOWN' then
                    HumaLike.SetStatus('unauthorized', 'license rejected by edge')
                    return
                end
                HumaLike.SetStatus('degraded', 'edge runtime state unavailable')
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
    HumaLike.ClearRuntimeCredentials()
end)
