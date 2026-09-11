local registrations = {}

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function signature(entity, entityId, networkId, modelHash, token, kind)
    return table.concat({ entity, entityId, networkId, modelHash, token, kind }, ':')
end

local function ambientIdentityMatches(npcId, entry, ped, networkId)
    if not NetworkGetEntityIsNetworked(ped) then return false end
    if NetworkGetNetworkIdFromEntity(ped) ~= networkId
        or not NetworkDoesEntityExistWithNetworkId(networkId)
        or NetworkGetEntityFromNetworkId(networkId) ~= ped then return false end
    return Entity(ped).state.humalike_npc_id == npcId
        and tonumber(entry.network_id) == networkId
end

local function registrationFor(npcId, entry, ped, token, kind)
    if not ped or not DoesEntityExist(ped) or type(token) ~= 'string' or token == '' then return nil end
    local entityId = tonumber(entry.entity_id)
    local networkId = tonumber(entry.network_id) or NetworkGetNetworkIdFromEntity(ped)
    if not entityId or entityId <= 0 or not networkId or networkId <= 0 then return nil end
    if kind == 'ambient' and not ambientIdentityMatches(npcId, entry, ped, networkId) then
        return nil
    end
    local modelHash = unsignedHash(GetEntityModel(ped))
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

local function desiredRegistrations()
    local desired = {}
    for npcId, entry in pairs(KnownNpcs or {}) do
        local ped = ResolveNpcPed(npcId)
        local token = ped and DoesEntityExist(ped)
            and (Entity(ped).state.humalike_runtime_token or entry.runtime_token) or nil
        local value, valueSignature = registrationFor(npcId, entry, ped, token, 'persistent')
        if value then desired[npcId] = { value = value, signature = valueSignature } end
    end
    for npcId, entry in pairs(AmbientNpcEntries or {}) do
        local ped = AmbientPeds and AmbientPeds[npcId] or nil
        local value, valueSignature = registrationFor(
            npcId, entry, ped, entry.lease_token, 'ambient')
        if value then desired[npcId] = { value = value, signature = valueSignature } end
    end
    return desired
end

local function reconcile(force)
    local desired = desiredRegistrations()
    for npcId, current in pairs(registrations) do
        if not desired[npcId] then
            exports['humalike']:UnregisterNpc(npcId)
            registrations[npcId] = nil
        elseif force or desired[npcId].signature ~= current then
            local ok = exports['humalike']:RegisterNpc(desired[npcId].value)
            if ok then registrations[npcId] = desired[npcId].signature end
        end
    end
    for npcId, candidate in pairs(desired) do
        if not registrations[npcId] then
            local ok = exports['humalike']:RegisterNpc(candidate.value)
            if ok then registrations[npcId] = candidate.signature end
        end
    end
end

local function registerOne(npcId, entry, ped, token, kind)
    if type(npcId) ~= 'string' or type(entry) ~= 'table' then return false end
    local value, valueSignature = registrationFor(npcId, entry, ped, token, kind)
    if not value then return false end
    if registrations[npcId] == valueSignature then return true end
    local ok = exports['humalike']:RegisterNpc(value)
    if ok then registrations[npcId] = valueSignature end
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
        reconcile(false)
        Wait(3000)
    end
end)
