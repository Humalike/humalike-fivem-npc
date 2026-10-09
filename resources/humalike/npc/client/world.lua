local registrations = {}

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function signature(entity, entityId, networkId, modelHash, token, kind)
    return table.concat({ entity, entityId, networkId, modelHash, token, kind }, ':')
end

local function ambientIdentityMatches(npcId, entry, ped, networkId)
    if not AmbientPedNpcIds or AmbientPedNpcIds[ped] ~= npcId then return false end
    return tonumber(entry.network_id) == networkId
        and NetworkGetNetworkIdFromEntity(ped) == networkId
end

local function registrationFor(npcId, entry, ped, token, kind, previous)
    if not ped or not DoesEntityExist(ped) or type(token) ~= 'string' or token == '' then return nil end
    local entityId = tonumber(entry.entity_id)
    local networkId = tonumber(entry.network_id) or NetworkGetNetworkIdFromEntity(ped)
    if not entityId or entityId <= 0 or not networkId or networkId <= 0 then return nil end
    if kind == 'ambient' and not ambientIdentityMatches(npcId, entry, ped, networkId) then
        return nil
    end
    local modelHash = previous and previous.entity == ped and previous.modelHash
        or unsignedHash(GetEntityModel(ped))
    return {
        npcId = npcId,
        entity = ped,
        entityId = entityId,
        networkId = networkId,
        modelHash = modelHash,
        runtimeToken = token,
        kind = kind,
    }, signature(ped, entityId, networkId, modelHash, token, kind)
end

-- The roster and the leases change while the pass is parked: it walks ids taken up front.
local SLICE = 8

local function previousOf(npcId)
    local current = registrations[npcId]
    return current and current.value or nil
end

local function desiredFor(npcId)
    local lease = AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
    if lease then
        local value, valueSignature = registrationFor(npcId, lease,
            AmbientPeds and AmbientPeds[npcId] or nil, lease.lease_token, 'ambient', previousOf(npcId))
        if value then return value, valueSignature end
    end
    local entry = KnownNpcs and KnownNpcs[npcId] or nil
    if not entry then return nil end
    local ped = ResolveNpcPed(npcId)
    local token = ped and DoesEntityExist(ped)
        and (Entity(ped).state.humalike_runtime_token or entry.runtime_token) or nil
    return registrationFor(npcId, entry, ped, token, 'persistent', previousOf(npcId))
end

local function reconcile(force, sliced)
    local ids, listed = {}, {}
    local function list(source)
        for npcId in pairs(source or {}) do
            if not listed[npcId] then
                listed[npcId] = true
                ids[#ids + 1] = npcId
            end
        end
    end
    list(registrations)
    list(KnownNpcs)
    list(AmbientNpcEntries)
    for index = 1, #ids do
        local npcId = ids[index]
        local value, valueSignature = desiredFor(npcId)
        local current = registrations[npcId]
        if not value then
            if current then
                exports['humalike']:UnregisterNpc(npcId)
                registrations[npcId] = nil
            end
        elseif not current or force or current.signature ~= valueSignature then
            local ok = exports['humalike']:RegisterNpc(value)
            if ok then registrations[npcId] = { value = value, signature = valueSignature } end
        end
        if sliced and index % SLICE == 0 then Wait(0) end
    end
end

local function registerOne(npcId, entry, ped, token, kind)
    if type(npcId) ~= 'string' or type(entry) ~= 'table' then return false end
    local value, valueSignature = registrationFor(npcId, entry, ped, token, kind, previousOf(npcId))
    if not value then return false end
    local current = registrations[npcId]
    if current and current.signature == valueSignature then return true end
    local ok = exports['humalike']:RegisterNpc(value)
    if ok then registrations[npcId] = { value = value, signature = valueSignature } end
    return ok == true
end

AddEventHandler('humalike:world:registrationRequested', function()
    registrations = {}
    reconcile(true)
end)

AddEventHandler('humalike:npc:npcRemoved', function(npcId)
    if registrations[npcId] then
        exports['humalike']:UnregisterNpc(npcId)
        registrations[npcId] = nil
    end
end)

AddEventHandler('humalike:npc:ambientPedRemoved', function(npcId)
    if registrations[npcId] then
        exports['humalike']:UnregisterNpc(npcId)
        registrations[npcId] = nil
    end
end)

AddEventHandler('humalike:npc:persistentPedAssigned', function(npcId, ped, entry)
    local token = ped and DoesEntityExist(ped)
        and (Entity(ped).state.humalike_runtime_token or (entry and entry.runtime_token)) or nil
    registerOne(npcId, entry, ped, token, 'persistent')
end)

AddEventHandler('humalike:npc:persistentPedRemoved', function(npcId)
    if registrations[npcId] then
        exports['humalike']:UnregisterNpc(npcId)
        registrations[npcId] = nil
    end
end)

AddEventHandler('humalike:npc:ambientPedAssigned', function(npcId, ped, entry)
    registerOne(npcId, entry, ped, entry and entry.lease_token, 'ambient')
end)

CreateThread(function()
    while true do
        reconcile(false, true)
        Wait(5000)
    end
end)
