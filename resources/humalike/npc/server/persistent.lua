
PersistentNpcEntities = {}
local bindingInFlight = {}
local bindingRemovalPending = {}
local bindingRemovalCount = {}
local deferredBinding = {}

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function activeEntity(npcId)
    local external = HumalikeNpcEntityOwnership
        and HumalikeNpcEntityOwnership.ExternalEntity(npcId)
    return external or PersistentNpcEntities[npcId]
end

function RegisterPersistentNpcBinding(entry, ped)
    if (bindingRemovalCount[entry.npc_id] or 0) > 0 then
        deferredBinding[entry.npc_id] = { entry = entry, ped = ped }
        return
    end
    local credentials = HumaLike.RuntimeCredentials()
    if not credentials then return end
    local networkId = NetworkGetNetworkIdFromEntity(ped)
    if networkId <= 0 then return end
    local assignment = HumaLike.EdgeAssignmentKey()
    local activeRequest = bindingInFlight[entry.npc_id]
    if activeRequest and activeRequest.ped == ped
        and activeRequest.assignment == assignment then return end
    local request = { ped = ped, assignment = assignment }
    bindingInFlight[entry.npc_id] = request
    entry.entity_id = ped
    entry.network_id = networkId
    HumalikeHttp.PostAction('upsert_npc_runtime_binding', {
        boot_id = credentials.bootId,
        npc_id = entry.npc_id,
        entity_id = ped,
        network_id = networkId,
        model_hash = unsignedHash(GetEntityModel(ped)),
        routing_bucket = GetEntityRoutingBucket(ped),
    }, function(ok, _, body)
        if bindingInFlight[entry.npc_id] ~= request then return end
        bindingInFlight[entry.npc_id] = nil
        if not HumaLike.IsCurrentEdgeAssignment(assignment) then return end
        if not ok or not body or type(body.runtime_token) ~= 'string' then return end
        if activeEntity(entry.npc_id) ~= ped or not DoesEntityExist(ped)
            or NetworkGetNetworkIdFromEntity(ped) ~= networkId then
            RemovePersistentNpcRuntimeBinding(entry.npc_id, body.runtime_token)
            return
        end
        local currentEntry = NpcRegistry and NpcRegistry[entry.npc_id] or entry
        local tokenChanged = currentEntry.runtime_token ~= body.runtime_token
        currentEntry.runtime_token = body.runtime_token
        Entity(ped).state:set('humalike_runtime_token', body.runtime_token, true)
        if HumalikeNpcEntityOwnership then
            HumalikeNpcEntityOwnership.SetRuntimeToken(entry.npc_id, ped, body.runtime_token)
        end
        if tokenChanged then TriggerClientEvent('humalike:npc:npcAdded', -1, currentEntry) end
    end)
end

local function replayBindings(clearRemovals)
    bindingInFlight = {}
    if clearRemovals then
        bindingRemovalPending = {}
        bindingRemovalCount = {}
        deferredBinding = {}
    end
    for npcId, entry in pairs(NpcRegistry or {}) do
        local entity = activeEntity(npcId)
        if entity and DoesEntityExist(entity) then
            entry.runtime_token = nil
            Entity(entity).state:set('humalike_runtime_token', nil, true)
            if HumalikeNpcEntityOwnership then
                HumalikeNpcEntityOwnership.SetRuntimeToken(npcId, entity, nil)
            end
            RegisterPersistentNpcBinding(entry, entity)
        end
    end
end

local function scheduleBindingRemovalRetry(key, request)
    local delay = math.min(500 * (2 ^ math.min(request.attempt - 1, 6)), 30000)
    request.retryGeneration = request.retryGeneration + 1
    local generation = request.retryGeneration
    SetTimeout(delay, function()
        if bindingRemovalPending[key] ~= request
            or request.retryGeneration ~= generation then return end
        RemovePersistentNpcRuntimeBinding(
            request.npcId, request.runtimeToken, request.attempt + 1, request)
    end)
end

function RemovePersistentNpcRuntimeBinding(npcId, runtimeToken, attempt, request)
    if type(runtimeToken) ~= 'string' or runtimeToken == '' then return end
    local key = npcId .. ':' .. runtimeToken
    if not attempt then
        if bindingRemovalPending[key] then return end
        request = {
            npcId = npcId,
            runtimeToken = runtimeToken,
            attempt = 0,
            retryGeneration = 0,
            inFlight = false,
        }
        bindingRemovalPending[key] = request
        bindingRemovalCount[npcId] = (bindingRemovalCount[npcId] or 0) + 1
    elseif bindingRemovalPending[key] ~= request then
        return
    end
    attempt = attempt or 1
    if request.inFlight then return end
    request.attempt = attempt
    request.retryGeneration = request.retryGeneration + 1
    local credentials = HumaLike.RuntimeCredentials()
    if not credentials then
        scheduleBindingRemovalRetry(key, request)
        return
    end
    request.inFlight = true
    HumalikeHttp.PostAction('remove_npc_runtime_binding', {
        boot_id = credentials.bootId,
        npc_id = npcId,
        runtime_token = runtimeToken,
    }, function(ok)
        if bindingRemovalPending[key] ~= request then return end
        request.inFlight = false
        if ok then
            bindingRemovalPending[key] = nil
            bindingRemovalCount[npcId] = math.max(0, (bindingRemovalCount[npcId] or 1) - 1)
            if bindingRemovalCount[npcId] == 0 then
                bindingRemovalCount[npcId] = nil
                local deferred = deferredBinding[npcId]
                deferredBinding[npcId] = nil
                if deferred then
                    RegisterPersistentNpcBinding(deferred.entry, deferred.ped)
                end
            end
            return
        end
        scheduleBindingRemovalRetry(key, request)
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
    if entry.type == 'external' then
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
        entry.entity_id, entry.network_id, entry.runtime_token = nil, nil, nil
        return nil
    end
    if HumalikeNpcEntityOwnership then
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
                if entry and entry.type == 'static' and EnsurePersistentNpc(entry) then
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

AddEventHandler('humalike:runtime:edgeChanged', function()
    replayBindings(true)
end)
AddEventHandler('humalike:runtime:refreshed', function(runtime)
    if runtime and runtime.edgeChanged == true then return end
    replayBindings(false)
    for _, request in pairs(bindingRemovalPending) do
        RemovePersistentNpcRuntimeBinding(
            request.npcId, request.runtimeToken, request.attempt + 1, request)
    end
end)
