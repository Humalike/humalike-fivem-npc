AmbientInteractionAdapters = AmbientInteractionAdapters or {}

local API_VERSION = 1

local function randomHex(length)
    local value = ''
    for _ = 1, length do value = value .. ('%x'):format(math.random(0, 15)) end
    return value
end

local runtimeEpoch = randomHex(8) .. '-' .. randomHex(8)

local registry = HumalikeProviderRegistry.new({
    domain = 'interaction', label = 'interaction provider', noun = 'provider',
    adapters = AmbientInteractionAdapters,
})
local callable = HumalikeProviderRegistry.callable
local validName = HumalikeProviderRegistry.validName
local call = registry.call

local function resolve(notify, previousOverride)
    local previous = registry.selectedName
    local previousAdapter = previousOverride
        or previous and AmbientInteractionAdapters[previous] or nil
    local selected = registry.resolve()
    if notify and previous ~= registry.selectedName then
        TriggerEvent('humalike:interaction:providerChanged',
            registry.selectedName, previous, previousAdapter)
    end
    return selected
end

exports('RegisterInteractionProvider', function(descriptor)
    local owner = GetInvokingResource()
    if not owner or type(descriptor) ~= 'table'
        or descriptor.apiVersion ~= API_VERSION
        or not registry.validDescriptor(descriptor, { 'Add', 'Remove' }, { 'Progress' }) then
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

local function interactionProviderStatus()
    local status = registry.status()
    status.apiVersion = API_VERSION
    status.runtimeEpoch = runtimeEpoch
    return status
end

exports('GetInteractionProviderStatus', interactionProviderStatus)

function HumalikeInteractionAdapter()
    return resolve(false)
end

function HumalikeInteractionAdapterByName(name)
    return name and AmbientInteractionAdapters[name] or nil
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
            if name == registry.selectedName then removedSelected = adapter end
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
