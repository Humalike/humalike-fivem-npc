AmbientPeds = {}
AmbientNpcEntries = {}
AmbientPedNpcIds = {} -- ped -> npc id, the reverse of AmbientPeds, so nobody reads the bag for it

local desiredAmbientLeases = {}
local voiceMuteRevision = -1

RegisterNetEvent('humalike:npc:voiceMuteSnapshot')
AddEventHandler('humalike:npc:voiceMuteSnapshot', function(revision, states)
    revision = tonumber(revision)
    if not revision or revision <= voiceMuteRevision or type(states) ~= 'table' then return end
    voiceMuteRevision = revision
    for npcId, entry in pairs(KnownNpcs or {}) do
        entry.voice_muted = states[npcId] == true
    end
    for npcId, entry in pairs(AmbientNpcEntries) do
        entry.voice_muted = states[npcId] == true
    end
end)

local function pedForNetworkId(networkId)
    if type(networkId) ~= 'number' or networkId <= 0
        or not NetworkDoesEntityExistWithNetworkId(networkId) then return nil end
    local ped = NetworkGetEntityFromNetworkId(networkId)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

local function removeAmbientAssignment(npcId)
    local ped = AmbientPeds[npcId]
    local entry = AmbientNpcEntries[npcId]
    if ped then
        TriggerEvent('humalike:npc:ambientPedRemoved', npcId, ped, entry)
        if DoesEntityExist(ped) and Entity(ped).state.humalike_npc_id == npcId then
            Entity(ped).state:set('humalike_npc_id', nil, false)
        end
        if AmbientPedNpcIds[ped] == npcId then AmbientPedNpcIds[ped] = nil end
    end
    AmbientPeds[npcId] = nil
    AmbientNpcEntries[npcId] = nil
end

local function clearAmbientAssignments()
    local npcIds = {}
    for npcId in pairs(AmbientPeds) do npcIds[#npcIds + 1] = npcId end
    for _, npcId in ipairs(npcIds) do removeAmbientAssignment(npcId) end
end

local function bindAmbientLease(lease)
    local ped = pedForNetworkId(lease.network_id)
    if not ped or GetEntityType(ped) ~= 1 or IsPedAPlayer(ped) then return false end

    local npcId = lease.npc_id
    local previousPed = AmbientPeds[npcId]
    local previousEntry = AmbientNpcEntries[npcId]
    local changed = previousPed ~= ped or not previousEntry
        or previousEntry.entity_id ~= lease.entity_id
        or previousEntry.network_id ~= lease.network_id
        or previousEntry.lease_token ~= lease.lease_token
    if not changed then
        previousEntry.name = lease.display_name
        previousEntry.language = lease.language
        previousEntry.voice_muted = lease.voice_muted == true
        if Entity(ped).state.humalike_npc_id ~= npcId then
            Entity(ped).state:set('humalike_npc_id', npcId, false)
        end
        return true
    end
    if changed and previousPed then removeAmbientAssignment(npcId) end

    AmbientPeds[npcId] = ped
    AmbientPedNpcIds[ped] = npcId
    AmbientNpcEntries[npcId] = {
        name = lease.display_name,
        entity_id = lease.entity_id,
        network_id = lease.network_id,
        routing_bucket = lease.routing_bucket,
        lease_token = lease.lease_token,
        language = lease.language,
        voice_muted = lease.voice_muted == true,
        style_seed = lease.style_seed,
        style = lease.style,
    }
    Entity(ped).state:set('humalike_npc_id', npcId, false)
    if changed then
        TriggerEvent('humalike:npc:ambientPedAssigned', npcId, ped, AmbientNpcEntries[npcId])
    end
    return true
end

-- A bound lease is verified for two natives: the ped is still there and still
-- carries the lease's network id (a recycled id lands on another ped).
local function leaseIsBound(npcId, lease)
    local ped, entry = AmbientPeds[npcId], AmbientNpcEntries[npcId]
    if not ped or not entry
        or entry.entity_id ~= lease.entity_id
        or entry.network_id ~= lease.network_id
        or entry.lease_token ~= lease.lease_token
        or entry.routing_bucket ~= lease.routing_bucket
        or entry.name ~= lease.display_name
        or entry.language ~= lease.language
        or entry.voice_muted ~= (lease.voice_muted == true)
        or AmbientPedNpcIds[ped] ~= npcId then return false end
    return DoesEntityExist(ped) and NetworkGetNetworkIdFromEntity(ped) == lease.network_id
end

RegisterNetEvent('humalike:npc:ambientLeases')
AddEventHandler('humalike:npc:ambientLeases', function(payload)
    if not payload.enabled or type(payload.leases) ~= 'table' then
        desiredAmbientLeases = {}
        clearAmbientAssignments()
        return
    end

    local desired = {}
    for _, lease in ipairs(payload.leases) do
        if type(lease.npc_id) == 'string' and type(lease.network_id) == 'number'
            and type(lease.lease_token) == 'string' then
            desired[lease.npc_id] = lease
        end
    end
    desiredAmbientLeases = desired
    for npcId, lease in pairs(desired) do
        if not leaseIsBound(npcId, lease) then bindAmbientLease(lease) end
    end
    local removed = {}
    for npcId in pairs(AmbientPeds) do
        if not desired[npcId] then removed[#removed + 1] = npcId end
    end
    for _, npcId in ipairs(removed) do removeAmbientAssignment(npcId) end
end)

CreateThread(function()
    while true do
        local unresolved = false
        for npcId, lease in pairs(desiredAmbientLeases) do
            if not leaseIsBound(npcId, lease) then
                unresolved = true
                local ped = AmbientPeds[npcId]
                if ped then removeAmbientAssignment(npcId) end
                bindAmbientLease(lease)
            end
        end
        Wait(unresolved and 500 or 2000)
    end
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('humalike:npc:requestAmbientLeaseSnapshot')
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        desiredAmbientLeases = {}
        clearAmbientAssignments()
    end
end)
