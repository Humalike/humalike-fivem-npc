
PersistentNpcEntities = {}
local bindingInFlight = {}
local bindingRemovalPending = {}

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function activeEntity(npcId)
    local external = HumalikeNpcEntityOwnership
        and HumalikeNpcEntityOwnership.ExternalEntity(npcId)
    return external or PersistentNpcEntities[npcId]
end

function RegisterPersistentNpcBinding(entry, ped)
    if not HumaLike.RuntimeCredentials() then return end
    local networkId = NetworkGetNetworkIdFromEntity(ped)
    if networkId <= 0 then return end
    if bindingInFlight[entry.npc_id] == ped then return end
    bindingInFlight[entry.npc_id] = ped
    entry.entity_id = ped
    entry.network_id = networkId
    HumalikeHttp.PostAction('upsert_npc_runtime_binding', {
        npc_id = entry.npc_id,
        entity_id = ped,
        network_id = networkId,
        model_hash = unsignedHash(GetEntityModel(ped)),
        routing_bucket = GetEntityRoutingBucket(ped),
    }, function(ok, _, body)
        if bindingInFlight[entry.npc_id] == ped then bindingInFlight[entry.npc_id] = nil end
        if not ok or not body or type(body.runtime_token) ~= 'string' then return end
        if activeEntity(entry.npc_id) ~= ped or not DoesEntityExist(ped)
            or NetworkGetNetworkIdFromEntity(ped) ~= networkId then return end
        local tokenChanged = entry.runtime_token ~= body.runtime_token
        entry.runtime_token = body.runtime_token
        Entity(ped).state:set('humalike_runtime_token', body.runtime_token, true)
        if HumalikeNpcEntityOwnership then
            HumalikeNpcEntityOwnership.SetRuntimeToken(entry.npc_id, ped, body.runtime_token)
        end
        if tokenChanged then TriggerClientEvent('humalike:npc:npcAdded', -1, entry) end
    end)
end

function RemovePersistentNpcRuntimeBinding(npcId, runtimeToken, attempt)
    if type(runtimeToken) ~= 'string' or runtimeToken == '' then return end
    local key = npcId .. ':' .. runtimeToken
    if not attempt then
        if bindingRemovalPending[key] then return end
        bindingRemovalPending[key] = true
    end
    attempt = attempt or 1
    HumalikeHttp.PostAction('remove_npc_runtime_binding', {
        npc_id = npcId,
        runtime_token = runtimeToken,
    }, function(ok)
        if ok then
            bindingRemovalPending[key] = nil
            return
        end
        local delay = math.min(500 * (2 ^ math.min(attempt - 1, 6)), 30000)
        SetTimeout(delay, function()
            RemovePersistentNpcRuntimeBinding(npcId, runtimeToken, attempt + 1)
        end)
    end)
end

function PreparePersistentNpcEntity(entry, ped)
    local state = Entity(ped).state
    state:set('humalike_npc_id', entry.npc_id, true)
    state:set('humalike_npc_kind', 'persistent', true)
    local owner = NetworkGetEntityOwner(ped)
    if state.humalike_position_reporter ~= owner then
        state:set('humalike_position_reporter', owner, true)
    end
end

function EnsurePersistentNpc(entry, refreshBinding)
    if HumalikeNpcEntityOwnership then
        local external = HumalikeNpcEntityOwnership.ExternalEntity(entry.npc_id)
        if external then
            entry.entity_id = external
            entry.network_id = NetworkGetNetworkIdFromEntity(external)
            PreparePersistentNpcEntity(entry, external)
            if refreshBinding or type(entry.runtime_token) ~= 'string' then
                RegisterPersistentNpcBinding(entry, external)
            end
            return external
        end
        if HumalikeNpcEntityOwnership.IsDespawned(entry.npc_id) then
            entry.entity_id, entry.network_id, entry.runtime_token = nil, nil, nil
            return nil
        end
    end
    local existing = PersistentNpcEntities[entry.npc_id]
    if existing and DoesEntityExist(existing) then
        entry.entity_id = existing
        entry.network_id = NetworkGetNetworkIdFromEntity(existing)
        if refreshBinding or type(entry.runtime_token) ~= 'string' then
            RegisterPersistentNpcBinding(entry, existing)
        end
        return existing
    end
    local ped = CreatePed(4, GetHashKey(entry.model), entry.x, entry.y, entry.z,
        entry.heading, true, true)
    if not ped or ped == 0 then
        print(('[humalike-npc] server CreatePed failed for npc %s'):format(entry.npc_id))
        return nil
    end
    SetEntityRoutingBucket(ped, 0)
    SetEntityOrphanMode(ped, 2)
    PreparePersistentNpcEntity(entry, ped)
    PersistentNpcEntities[entry.npc_id] = ped
    entry.entity_id = ped
    local networkId = NetworkGetNetworkIdFromEntity(ped)
    local attempts = 0
    while networkId <= 0 and attempts < 50 do
        Wait(0)
        attempts = attempts + 1
        networkId = NetworkGetNetworkIdFromEntity(ped)
    end
    entry.network_id = networkId
    RegisterPersistentNpcBinding(entry, ped)
    local pose = NpcPoses and NpcPoses[entry.npc_id]
    if pose then
        ReplayNpcPoseWhenReady(entry.npc_id, pose,
            function() return DoesEntityExist(ped) end,
            function()
                if HumalikeNpcRuntimeControl then
                    local allowed = HumalikeNpcRuntimeControl.AllowsAction(entry.npc_id, pose)
                    if not allowed then return true end
                end
                local reporter = Entity(ped).state.humalike_position_reporter
                if type(reporter) ~= 'number' or not GetPlayerName(reporter) then
                    return false
                end
                TriggerClientEvent('humalike:npc:playAction', -1, entry.npc_id, pose, {})
                return true
            end)
    end
    return ped
end

function RemovePersistentNpc(npcId)
    local ped = PersistentNpcEntities[npcId]
    PersistentNpcEntities[npcId] = nil
    if ped and DoesEntityExist(ped) then
        local state = Entity(ped).state
        if state.humalike_npc_id == npcId then
            state:set('humalike_npc_id', nil, true)
            state:set('humalike_npc_kind', nil, true)
            state:set('humalike_runtime_token', nil, true)
            state:set('humalike_position_reporter', nil, true)
            state:set('humalike_action', nil, true)
        end
        DeleteEntity(ped)
    end
end

CreateThread(function()
    while true do
        Wait(2000)
        if HumalikeNpcEntityOwnership then HumalikeNpcEntityOwnership.Reconcile() end
        for npcId, ped in pairs(PersistentNpcEntities) do
            if not DoesEntityExist(ped) then
                PersistentNpcEntities[npcId] = nil
                local entry = NpcRegistry and NpcRegistry[npcId]
                if entry and EnsurePersistentNpc(entry) then
                    TriggerClientEvent('humalike:npc:npcAdded', -1, entry)
                end
            else
                local entry = NpcRegistry and NpcRegistry[npcId]
                if entry then PreparePersistentNpcEntity(entry, ped) end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for npcId in pairs(PersistentNpcEntities) do RemovePersistentNpc(npcId) end
end)
