HumalikeNpcEntityOwnership = HumalikeNpcEntityOwnership or {}

local bindingsById, bindingByNpc, bindingByNetwork = {}, {}, {}
local despawnByNpc = {}
local sequence = 0

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function owner()
    local resource = GetInvokingResource()
    if not resource or resource == GetCurrentResourceName() then return nil end
    return resource
end

local function nextId(invoking)
    sequence = sequence + 1
    local credentials = HumaLike and HumaLike.RuntimeCredentials()
    return ('%s:%s:%d'):format(invoking, credentials and credentials.bootId or 'boot', sequence)
end

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function clearEntry(entry)
    entry.entity_id, entry.network_id, entry.runtime_token = nil, nil, nil
end

local function publicBinding(record)
    local result = copy(record)
    result.entity, result.modelHash, result.runtimeToken = nil, nil, nil
    return result
end

local function clearEntityState(record)
    local entity = record.entity
    if not entity or not DoesEntityExist(entity) then return end
    local state = Entity(entity).state
    if state.humalike_npc_id ~= record.npcId then return end
    state:set('humalike_npc_id', nil, true)
    state:set('humalike_npc_kind', nil, true)
    state:set('humalike_runtime_token', nil, true)
    state:set('humalike_position_reporter', nil, true)
    state:set('humalike_action', nil, true)
end

local function invalidate(npcId, token)
    if RemovePersistentNpcRuntimeBinding then
        RemovePersistentNpcRuntimeBinding(npcId, token)
    end
end

local function detach(record, notify)
    if not record or bindingsById[record.id] ~= record then return false end
    bindingsById[record.id] = nil
    bindingByNpc[record.npcId] = nil
    bindingByNetwork[record.networkId] = nil
    clearEntityState(record)
    invalidate(record.npcId, record.runtimeToken)
    local entry = NpcRegistry and NpcRegistry[record.npcId]
    if entry then clearEntry(entry) end
    if notify ~= false then TriggerClientEvent('humalike:npc:npcRemoved', -1, record.npcId) end
    return true
end

function HumalikeNpcEntityOwnership.ExternalEntity(npcId)
    local record = bindingByNpc[npcId]
    if not record then return nil end
    local entity = NetworkGetEntityFromNetworkId(record.networkId)
    if entity == 0 or entity ~= record.entity or not DoesEntityExist(entity)
        or GetEntityType(entity) ~= 1 or IsPedAPlayer(entity)
        or unsignedHash(GetEntityModel(entity)) ~= record.modelHash
        or GetEntityRoutingBucket(entity) ~= record.routingBucket then
        detach(record)
        return nil
    end
    return entity
end

function HumalikeNpcEntityOwnership.IsDespawned(npcId)
    return despawnByNpc[npcId] ~= nil
end

function HumalikeNpcEntityOwnership.SuppressedStaticNpcIds()
    local result = {}
    for npcId in pairs(despawnByNpc) do result[#result + 1] = npcId end
    table.sort(result)
    return result
end

function HumalikeNpcEntityOwnership.SetRuntimeToken(npcId, entity, token)
    local record = bindingByNpc[npcId]
    if record and record.entity == entity then record.runtimeToken = token end
end

function HumalikeNpcEntityOwnership.State(npcId)
    local binding = bindingByNpc[npcId]
    if binding then
        return {
            entityOwner = 'external', bindingId = binding.id,
            ownerResource = binding.ownerResource, routingBucket = binding.routingBucket,
        }
    end
    local despawn = despawnByNpc[npcId]
    if despawn then
        return {
            entityOwner = 'despawned', despawnId = despawn.id,
            ownerResource = despawn.ownerResource,
        }
    end
    local entry = NpcRegistry and NpcRegistry[npcId]
    return { entityOwner = entry and entry.type == 'external' and 'external' or 'humalike' }
end

function HumalikeNpcEntityOwnership.ForgetNpc(npcId)
    local binding = bindingByNpc[npcId]
    if binding then detach(binding, false) end
    if despawnByNpc[npcId] then
        despawnByNpc[npcId] = nil
        HumalikeNpcRuntimeState.Publish()
    end
end

function HumalikeNpcEntityOwnership.DefinitionChanged(npcId, nextKind)
    local binding = bindingByNpc[npcId]
    if binding then detach(binding, false) end
    if nextKind ~= 'static' and despawnByNpc[npcId] then
        despawnByNpc[npcId] = nil
        HumalikeNpcRuntimeState.Publish()
    end
end

function HumalikeNpcEntityOwnership.Reconcile()
    for npcId in pairs(copy(bindingByNpc)) do
        local entity = HumalikeNpcEntityOwnership.ExternalEntity(npcId)
        local entry = NpcRegistry and NpcRegistry[npcId]
        if entity and entry and entry.type == 'external' then
            PreparePersistentNpcEntity(entry, entity)
            if type(entry.runtime_token) ~= 'string' then
                RegisterPersistentNpcBinding(entry, entity)
            end
        elseif entity then
            detach(bindingByNpc[npcId])
        end
    end
end

function HumalikeNpcEntityOwnership.Resync()
    for npcId, record in pairs(bindingByNpc) do
        record.runtimeToken = nil
        local entry = NpcRegistry and NpcRegistry[npcId]
        if entry then
            entry.runtime_token = nil
            RegisterPersistentNpcBinding(entry, record.entity)
        end
    end
end

exports('BindNpcEntity', function(npcId, networkId, options)
    local invoking = owner()
    if not invoking then return HumalikeExportResult.Failure('external_resource_required') end
    if type(npcId) ~= 'string' or npcId == '' or #npcId > 64 then
        return HumalikeExportResult.Failure('invalid_npc_id')
    end
    if type(networkId) ~= 'number' or networkId % 1 ~= 0 or networkId <= 0 then
        return HumalikeExportResult.Failure('invalid_network_id')
    end
    options = options or {}
    if type(options) ~= 'table' then return HumalikeExportResult.Failure('invalid_options') end
    local requestedBucket = options.routingBucket
    if requestedBucket ~= nil and (type(requestedBucket) ~= 'number'
        or requestedBucket % 1 ~= 0 or requestedBucket < 0) then
        return HumalikeExportResult.Failure('invalid_routing_bucket')
    end
    local entry = NpcRegistry and NpcRegistry[npcId]
    if not entry then return HumalikeExportResult.Failure('npc_not_found') end
    if entry.type ~= 'external' then return HumalikeExportResult.Failure('npc_not_external') end
    if bindingByNpc[npcId] then HumalikeNpcEntityOwnership.ExternalEntity(npcId) end
    local networkOwner = bindingByNetwork[networkId]
    if networkOwner then HumalikeNpcEntityOwnership.ExternalEntity(networkOwner.npcId) end
    local existing = bindingByNpc[npcId]
    if existing and existing.ownerResource == invoking and existing.networkId == networkId then
        if requestedBucket ~= nil and requestedBucket ~= existing.routingBucket then
            return HumalikeExportResult.Failure('routing_bucket_mismatch')
        end
        return HumalikeExportResult.Success(publicBinding(existing))
    end
    if existing then return HumalikeExportResult.Failure('npc_ownership_conflict') end
    if bindingByNetwork[networkId] then
        return HumalikeExportResult.Failure('entity_ownership_conflict')
    end
    local entity = NetworkGetEntityFromNetworkId(networkId)
    if entity == 0 or not DoesEntityExist(entity) then
        return HumalikeExportResult.Failure('entity_not_found')
    end
    if GetEntityType(entity) ~= 1 then return HumalikeExportResult.Failure('entity_not_ped') end
    if IsPedAPlayer(entity) then return HumalikeExportResult.Failure('player_ped_not_allowed') end
    if Entity(entity).state.humalike_npc_id ~= nil then
        return HumalikeExportResult.Failure('entity_already_humalike')
    end
    local modelHash = unsignedHash(GetEntityModel(entity))
    if modelHash ~= unsignedHash(GetHashKey(entry.model)) then
        return HumalikeExportResult.Failure('model_mismatch')
    end
    local actualBucket = GetEntityRoutingBucket(entity)
    if requestedBucket ~= nil and requestedBucket ~= actualBucket then
        return HumalikeExportResult.Failure('routing_bucket_mismatch')
    end

    local record = {
        apiVersion = 1, id = nextId(invoking), npcId = npcId,
        networkId = networkId, entity = entity, modelHash = modelHash,
        routingBucket = actualBucket, ownerResource = invoking,
    }
    bindingsById[record.id] = record
    bindingByNpc[npcId] = record
    bindingByNetwork[networkId] = record
    PreparePersistentNpcEntity(entry, entity)
    entry.entity_id, entry.network_id = entity, networkId
    RegisterPersistentNpcBinding(entry, entity)
    return HumalikeExportResult.Success(publicBinding(record))
end)

exports('UnbindNpcEntity', function(bindingId)
    local invoking = owner()
    if not invoking then return HumalikeExportResult.Failure('external_resource_required') end
    local record = type(bindingId) == 'string' and bindingsById[bindingId] or nil
    if not record then return HumalikeExportResult.Failure('binding_not_found') end
    if record.ownerResource ~= invoking then return HumalikeExportResult.Failure('not_owner') end
    detach(record)
    return HumalikeExportResult.Success()
end)

exports('DespawnNpc', function(npcId)
    local invoking = owner()
    if not invoking then return HumalikeExportResult.Failure('external_resource_required') end
    local entry = type(npcId) == 'string' and NpcRegistry and NpcRegistry[npcId] or nil
    if not entry then return HumalikeExportResult.Failure('npc_not_found') end
    if entry.type ~= 'static' then return HumalikeExportResult.Failure('npc_not_static') end
    local existing = despawnByNpc[npcId]
    if existing then
        if existing.ownerResource ~= invoking then return HumalikeExportResult.Failure('not_owner') end
        local result = copy(existing)
        result.runtimeToken = nil
        return HumalikeExportResult.Success(result)
    end
    if type(entry.runtime_token) ~= 'string' then
        return HumalikeExportResult.Failure('runtime_binding_unavailable')
    end
    local record = {
        apiVersion = 1, id = nextId(invoking), npcId = npcId,
        ownerResource = invoking, runtimeToken = entry.runtime_token,
    }
    despawnByNpc[npcId] = record
    TriggerClientEvent('humalike:npc:npcRemoved', -1, npcId)
    RemovePersistentNpc(npcId)
    invalidate(npcId, record.runtimeToken)
    clearEntry(entry)
    HumalikeNpcRuntimeState.Publish()
    local result = copy(record)
    result.runtimeToken = nil
    return HumalikeExportResult.Success(result)
end)

exports('RespawnNpc', function(npcId)
    local invoking = owner()
    if not invoking then return HumalikeExportResult.Failure('external_resource_required') end
    local record = type(npcId) == 'string' and despawnByNpc[npcId] or nil
    if not record then return HumalikeExportResult.Failure('despawn_not_found') end
    if record.ownerResource ~= invoking then return HumalikeExportResult.Failure('not_owner') end
    despawnByNpc[npcId] = nil
    HumalikeNpcRuntimeState.Publish()
    local entry = NpcRegistry and NpcRegistry[npcId]
    local entity = entry and EnsurePersistentNpc(entry) or nil
    if entity then TriggerClientEvent('humalike:npc:npcAdded', -1, entry) end
    if not entity then return HumalikeExportResult.Failure('spawn_failed') end
    return HumalikeExportResult.Success()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        for _, record in pairs(copy(bindingsById)) do clearEntityState(record) end
        return
    end
    for _, record in pairs(copy(bindingsById)) do
        if record.ownerResource == resourceName then detach(record) end
    end
    for npcId, record in pairs(copy(despawnByNpc)) do
        if record.ownerResource == resourceName then
            despawnByNpc[npcId] = nil
            HumalikeNpcRuntimeState.Publish()
            local entry = NpcRegistry and NpcRegistry[npcId]
            local entity = entry and EnsurePersistentNpc(entry) or nil
            if entity then TriggerClientEvent('humalike:npc:npcAdded', -1, entry) end
        end
    end
end)

AddEventHandler('humalike:core:ready', function()
    HumalikeNpcEntityOwnership.Resync()
end)
