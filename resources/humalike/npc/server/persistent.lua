
PersistentNpcEntities = {}

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function registerBinding(entry, ped)
    if not HumaLike.RuntimeCredentials() then return end
    local networkId = NetworkGetNetworkIdFromEntity(ped)
    if networkId <= 0 then return end
    entry.entity_id = ped
    entry.network_id = networkId
    HumalikeHttp.PostAction('upsert_npc_runtime_binding', {
        npc_id = entry.npc_id,
        entity_id = ped,
        network_id = networkId,
        model_hash = unsignedHash(GetEntityModel(ped)),
        routing_bucket = GetEntityRoutingBucket(ped),
    }, function(ok, _, body)
        if not ok or not body or type(body.runtime_token) ~= 'string' then return end
        if PersistentNpcEntities[entry.npc_id] ~= ped or not DoesEntityExist(ped)
            or NetworkGetNetworkIdFromEntity(ped) ~= networkId then return end
        local tokenChanged = entry.runtime_token ~= body.runtime_token
        entry.runtime_token = body.runtime_token
        Entity(ped).state:set('humalike_runtime_token', body.runtime_token, true)
        if tokenChanged then TriggerClientEvent('humalike:npc:npcAdded', -1, entry) end
    end)
end

function EnsurePersistentNpc(entry, refreshBinding)
    local existing = PersistentNpcEntities[entry.npc_id]
    if existing and DoesEntityExist(existing) then
        entry.entity_id = existing
        entry.network_id = NetworkGetNetworkIdFromEntity(existing)
        if refreshBinding or type(entry.runtime_token) ~= 'string' then
            registerBinding(entry, existing)
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
    Entity(ped).state:set('humalike_npc_id', entry.npc_id, true)
    Entity(ped).state:set('humalike_npc_kind', 'persistent', true)
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
    registerBinding(entry, ped)
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
    if ped and DoesEntityExist(ped) then DeleteEntity(ped) end
end

CreateThread(function()
    while true do
        Wait(2000)
        for npcId, ped in pairs(PersistentNpcEntities) do
            if not DoesEntityExist(ped) then
                PersistentNpcEntities[npcId] = nil
                local entry = NpcRegistry and NpcRegistry[npcId]
                if entry and EnsurePersistentNpc(entry) then
                    TriggerClientEvent('humalike:npc:npcAdded', -1, entry)
                end
            else
                local owner = NetworkGetEntityOwner(ped)
                local state = Entity(ped).state
                if state.humalike_position_reporter ~= owner then
                    state:set('humalike_position_reporter', owner, true)
                end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for npcId in pairs(PersistentNpcEntities) do RemovePersistentNpc(npcId) end
end)
