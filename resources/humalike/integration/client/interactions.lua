AmbientInteractionAdapters = AmbientInteractionAdapters or {}

local selectedName = nil
local resolution = { state = 'unresolved' }
local API_VERSION = 1

local function randomHex(length)
    local value = ''
    for _ = 1, length do value = value .. ('%x'):format(math.random(0, 15)) end
    return value
end

local runtimeEpoch = randomHex(8) .. '-' .. randomHex(8)

local function setting()
    return tostring((Config.Integrations or {}).interaction or 'auto'):lower()
end

local function available(adapter)
    if adapter.Available == nil then return true end
    local ok, result = pcall(adapter.Available)
    return ok and result == true
end

local function callable(value)
    return type(value) == 'function' or type(value) == 'table'
end

local function validName(value)
    return type(value) == 'string' and value:match('^[%w_.-]+$') ~= nil
        and value == value:lower() and value ~= 'none' and #value <= 64
end

local function reportFailure(adapter, method, message)
    local now = GetGameTimer()
    local failure = adapter.failure or { count = 0, suppressed = 0 }
    failure.count = failure.count + 1
    failure.method = method
    failure.message = tostring(message)
    failure.at = now
    if not failure.reportedAt or now - failure.reportedAt >= 10000 then
        local suffix = failure.suppressed > 0
            and (' (%d suppressed)'):format(failure.suppressed) or ''
        print(('[humalike] interaction provider %s.%s failed: %s%s'):format(
            adapter.name, method, failure.message, suffix))
        failure.reportedAt = now
        failure.suppressed = 0
    else
        failure.suppressed = failure.suppressed + 1
    end
    adapter.failure = failure
    if selectedName == adapter.name then
        resolution.state = 'degraded'
        resolution.reason = ('%s callback failed'):format(method)
    end
end

local function call(adapter, method, ...)
    if not adapter or not callable(adapter[method]) then return false, nil end
    local result = table.pack(pcall(adapter[method], ...))
    if not result[1] then
        reportFailure(adapter, method, result[2])
        return false, nil
    end
    adapter.failure = nil
    if selectedName == adapter.name then
        resolution.state = 'selected'
        resolution.reason = nil
    end
    return true, table.unpack(result, 2, result.n)
end

local function resolve(notify, previousOverride)
    local forced = setting()
    local previous = selectedName
    local previousAdapter = previousOverride
        or previous and AmbientInteractionAdapters[previous] or nil
    local eligible, highestPriority = {}, nil
    for name, adapter in pairs(AmbientInteractionAdapters) do
        adapter.name = name
        local priority = tonumber(adapter.priority) or 0
        if (forced == 'auto' or forced == name) and available(adapter) then
            if forced ~= 'auto' then
                eligible = { adapter }
                break
            elseif highestPriority == nil or priority > highestPriority then
                highestPriority = priority
                eligible = { adapter }
            elseif priority == highestPriority then
                eligible[#eligible + 1] = adapter
            end
        end
    end
    local selected
    if #eligible == 1 then
        selected = eligible[1]
        resolution = { state = selected.failure and 'degraded' or 'selected' }
    elseif #eligible > 1 then
        resolution = { state = 'ambiguous', reason = 'multiple providers share the highest priority' }
    elseif forced == 'none' then
        resolution = { state = 'disabled' }
    else
        resolution = { state = 'unavailable', reason = 'no available provider' }
    end
    selectedName = selected and selected.name or nil
    if notify and previous ~= selectedName then
        TriggerEvent('humalike:interaction:providerChanged',
            selectedName, previous, previousAdapter)
    end
    return selected
end

exports('RegisterInteractionProvider', function(descriptor)
    local owner = GetInvokingResource()
    if not owner or type(descriptor) ~= 'table'
        or descriptor.apiVersion ~= API_VERSION
        or not validName(descriptor.name)
        or type(descriptor.priority) ~= 'number'
        or descriptor.priority ~= descriptor.priority
        or math.abs(descriptor.priority) > 100000
        or not callable(descriptor.Add) or not callable(descriptor.Remove)
        or descriptor.Available ~= nil and not callable(descriptor.Available)
        or descriptor.Progress ~= nil and not callable(descriptor.Progress) then
        return false, 'invalid interaction provider'
    end
    local existing = AmbientInteractionAdapters[descriptor.name]
    if existing and existing.ownerResource ~= owner then
        return false, 'provider name already registered'
    end
    local adapter = {}
    for key, value in pairs(descriptor) do adapter[key] = value end
    adapter.ownerResource = owner
    adapter.priority = descriptor.priority
    AmbientInteractionAdapters[adapter.name] = adapter
    resolve(true)
    return true
end)

exports('UnregisterInteractionProvider', function(name)
    local owner = GetInvokingResource()
    if not owner or not validName(name) then return false, 'invalid provider' end
    local adapter = AmbientInteractionAdapters[name]
    if not adapter then return true end
    if adapter.ownerResource ~= owner then return false, 'provider owned by another resource' end
    AmbientInteractionAdapters[name] = nil
    resolve(true, adapter)
    return true
end)

-- Where the interaction setting comes from: set in server.cfg and received
-- (`server`), received but left at auto (`default`), or not received yet (`local`).
local function settingsSource()
    if not (HumalikeSettings and HumalikeSettings.applied) then return 'local' end
    local overrides = HumalikeConvars and HumalikeConvars.overrides or {}
    return overrides.humalike_interaction ~= nil and 'server' or 'default'
end

local function interactionProviderStatus()
    resolve(false)
    local selected = selectedName and AmbientInteractionAdapters[selectedName] or nil
    return {
        apiVersion = API_VERSION,
        runtimeEpoch = runtimeEpoch,
        setting = setting(),
        settingsSource = settingsSource(),
        state = resolution.state,
        reason = resolution.reason,
        selected = selected and {
            name = selected.name,
            ownerResource = selected.ownerResource,
            priority = selected.priority,
        } or false,
    }
end

exports('GetInteractionProviderStatus', interactionProviderStatus)

function HumalikeInteractionAdapter()
    return resolve(false)
end

function HumalikeInteractionAdapterByName(name)
    return name and AmbientInteractionAdapters[name] or nil
end

if type(RegisterCommand) == 'function' then
    RegisterCommand('humalike_status', function()
        local status = interactionProviderStatus()
        local selected = status.selected and status.selected.name or 'none'
        print(('[humalike] interaction setting=%s (%s) state=%s selected=%s%s'):format(
            status.setting,
            status.settingsSource,
            status.state,
            selected,
            status.reason and (' reason=%s'):format(status.reason) or ''
        ))
    end, false)
end

function HumalikeIsInteractionResource(resourceName)
    for _, adapter in pairs(AmbientInteractionAdapters or {}) do
        if adapter.resource == resourceName or adapter.ownerResource == resourceName then
            return true
        end
        for _, watched in ipairs(adapter.watchedResources or {}) do
            if watched == resourceName then return true end
        end
    end
    return false
end

AddEventHandler('humalike:settings:applied', function()
    resolve(true)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    resolve(true)
    if resourceName == GetCurrentResourceName() then
        TriggerEvent('humalike:integration:ready', {
            apiVersion = API_VERSION,
            runtimeEpoch = runtimeEpoch,
        })
    end
end)

function HumalikeInteractionAdd(adapter, id, entity, options)
    local ok, added = call(adapter, 'Add', id, entity, options)
    return ok and added == true
end

function HumalikeInteractionRemove(adapter, id)
    local ok = call(adapter, 'Remove', id)
    return ok
end

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    local watched = HumalikeIsInteractionResource(resourceName)
    local changed = false
    local removedSelected
    for name, adapter in pairs(AmbientInteractionAdapters) do
        if adapter.ownerResource == resourceName then
            if name == selectedName then removedSelected = adapter end
            AmbientInteractionAdapters[name] = nil
            changed = true
        end
    end
    if changed or watched then resolve(true, removedSelected) end
end)

function HumalikeInteractionProgress(durationMs, label, ped)
    local adapter = HumalikeInteractionAdapter()
    local completed
    if adapter and callable(adapter.Progress) then
        local ok, result = call(adapter, 'Progress', durationMs, label)
        completed = ok and result == true
    elseif GetResourceState('ox_lib') == 'started' then
        local ok, result = pcall(function()
            return exports.ox_lib:progressBar({
                duration = durationMs,
                label = label,
                canCancel = true,
                disable = { move = true, combat = true },
            })
        end)
        completed = ok and result == true
    else
        local startedAt = GetGameTimer()
        while GetGameTimer() - startedAt < durationMs do
            Wait(100)
            if ped and not DoesEntityExist(ped) then return false end
        end
        completed = true
    end
    if not completed then return false end
    if ped then
        local radius = (Config.Wounded or {}).LingerRadius or 20.0
        return DoesEntityExist(ped)
            and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped)) <= radius
    end
    return true
end
