local registrations = {}

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function signature(entity, entityId, networkId, modelHash, token, kind)
    return table.concat({ entity, entityId, networkId, modelHash, token, kind }, ':')
end

-- The lease module indexes leased peds by npc id; one native confirms the
-- handle still carries the lease's network id.
local function ambientIdentityMatches(npcId, entry, ped, networkId)
    if not AmbientPedNpcIds or AmbientPedNpcIds[ped] ~= npcId then return false end
    return tonumber(entry.network_id) == networkId
        and NetworkGetNetworkIdFromEntity(ped) == networkId
end

-- `previous` is the registration last made for this npc; a handle keeps its
-- model, so the hash is read once per ped.
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

-- The periodic pass yields every few NPCs so a crowd never lands on one frame.
local SLICE = 8

local function previousOf(npcId)
    local current = registrations[npcId]
    return current and current.value or nil
end

local function desiredRegistrations(sliced)
    local desired = {}
    local visited = 0
    local function step()
        visited = visited + 1
        if sliced and visited % SLICE == 0 then Wait(0) end
    end
    for npcId, entry in pairs(KnownNpcs or {}) do
        local ped = ResolveNpcPed(npcId)
        local token = ped and DoesEntityExist(ped)
            and (Entity(ped).state.humalike_runtime_token or entry.runtime_token) or nil
        local value, valueSignature = registrationFor(npcId, entry, ped, token, 'persistent', previousOf(npcId))
        if value then desired[npcId] = { value = value, signature = valueSignature } end
        step()
    end
    for npcId, entry in pairs(AmbientNpcEntries or {}) do
        local ped = AmbientPeds and AmbientPeds[npcId] or nil
        local value, valueSignature = registrationFor(
            npcId, entry, ped, entry.lease_token, 'ambient', previousOf(npcId))
        if value then desired[npcId] = { value = value, signature = valueSignature } end
        step()
    end
    return desired
end

local function reconcile(force, sliced)
    local desired = desiredRegistrations(sliced)
    for npcId, current in pairs(registrations) do
        if not desired[npcId] then
            exports['humalike']:UnregisterNpc(npcId)
            registrations[npcId] = nil
        elseif force or desired[npcId].signature ~= current.signature then
            local ok = exports['humalike']:RegisterNpc(desired[npcId].value)
            if ok then registrations[npcId] = desired[npcId] end
        end
    end
    for npcId, candidate in pairs(desired) do
        if not registrations[npcId] then
            local ok = exports['humalike']:RegisterNpc(candidate.value)
            if ok then registrations[npcId] = candidate end
        end
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
