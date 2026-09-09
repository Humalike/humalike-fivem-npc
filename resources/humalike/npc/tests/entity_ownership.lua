local exported, handlers, events, invalidations = {}, {}, {}, {}
local invoking = 'mission-one'
local exists = { [101] = true, [202] = true, [303] = true, [404] = true, [505] = true }
local networkEntities = { [52] = 202, [53] = 303, [54] = 404, [55] = 505 }
local types = { [101] = 1, [202] = 1, [303] = 2, [404] = 1, [505] = 1 }
local models = { [101] = 10, [202] = 10, [303] = 10, [404] = 10, [505] = 11 }
local buckets = { [101] = 0, [202] = 2, [303] = 2, [404] = 2, [505] = 2 }
local states = {}
local managed = 101
local runtimeStatePublishes = 0

NpcRegistry = {
    ['external-1'] = { npc_id = 'external-1', type = 'external', model = 'model-one' },
    ['static-1'] = {
        npc_id = 'static-1', type = 'static', model = 'model-one', entity_id = 101,
        network_id = 51, runtime_token = 'managed-token',
    },
}
HumaLike = { RuntimeCredentials = function() return { bootId = 'boot-1' } end }
HumalikeNpcRuntimeState = {
    Publish = function() runtimeStatePublishes = runtimeStatePublishes + 1 end,
}
function exports(name, callback) exported[name] = callback end
function GetInvokingResource() return invoking end
function GetCurrentResourceName() return 'humalike' end
function GetHashKey(model) return model == 'model-one' and 10 or 11 end
function NetworkGetEntityFromNetworkId(networkId) return networkEntities[networkId] or 0 end
function NetworkGetNetworkIdFromEntity(entity)
    for networkId, candidate in pairs(networkEntities) do
        if candidate == entity then return networkId end
    end
    return entity == 101 and 51 or 0
end
function DoesEntityExist(entity) return exists[entity] == true end
function GetEntityType(entity) return types[entity] or 0 end
function IsPedAPlayer(entity) return entity == 404 end
function GetEntityModel(entity) return models[entity] end
function GetEntityRoutingBucket(entity) return buckets[entity] end
function AddEventHandler(name, callback) handlers[name] = callback end
function TriggerClientEvent(name, target, npcId)
    events[#events + 1] = { name = name, target = target, npcId = npcId }
end
function Entity(entity)
    states[entity] = states[entity] or {}
    local state = states[entity]
    state.set = function(_, key, value) state[key] = value end
    return { state = state }
end
function RemovePersistentNpc(npcId)
    if npcId == 'static-1' then managed = nil end
end
function RemovePersistentNpcRuntimeBinding(npcId, token)
    invalidations[#invalidations + 1] = { npcId = npcId, token = token }
end
function PreparePersistentNpcEntity(entry, entity)
    states[entity] = states[entity] or {}
    states[entity].humalike_npc_id = entry.npc_id
end
function RegisterPersistentNpcBinding(entry, entity)
    entry.runtime_token = ('token-%d'):format(entity)
    HumalikeNpcEntityOwnership.SetRuntimeToken(entry.npc_id, entity, entry.runtime_token)
end
function EnsurePersistentNpc(entry)
    managed = 101
    entry.entity_id, entry.network_id, entry.runtime_token = 101, 51, 'restored-token'
    return 101
end

dofile('../server/core/export_result.lua')
dofile('server/entity_ownership.lua')

local function success(result)
    assert(result.apiVersion == 1 and result.ok == true and result.error == nil)
    return result.value
end

local function failure(result, expected)
    assert(result.apiVersion == 1 and result.ok == false and result.error == expected)
    assert(result.value == nil)
end

failure(exported.BindNpcEntity('static-1', 52, { routingBucket = 2 }), 'npc_not_external')
failure(exported.BindNpcEntity('external-1', 53, { routingBucket = 2 }), 'entity_not_ped')
failure(exported.BindNpcEntity('external-1', 54, { routingBucket = 2 }),
    'player_ped_not_allowed')
failure(exported.BindNpcEntity('external-1', 55, { routingBucket = 2 }), 'model_mismatch')
failure(exported.BindNpcEntity('external-1', 52, { routingBucket = 0 }),
    'routing_bucket_mismatch')

local binding = success(exported.BindNpcEntity('external-1', 52, { routingBucket = 2 }))
assert(binding.ownerResource == 'mission-one' and binding.networkId == 52)
assert(managed == 101, 'binding external NPC must not replace a static ped')
assert(states[202].humalike_npc_id == 'external-1')
assert(NpcRegistry['external-1'].entity_id == 202)
assert(HumalikeNpcEntityOwnership.State('external-1').entityOwner == 'external')
assert(success(exported.BindNpcEntity('external-1', 52, {})).id == binding.id)

invoking = 'mission-two'
failure(exported.UnbindNpcEntity(binding.id), 'not_owner')
invoking = 'mission-one'
assert(exported.UnbindNpcEntity(binding.id).ok)
assert(states[202].humalike_npc_id == nil and exists[202])
assert(NpcRegistry['external-1'].entity_id == nil)
assert(managed == 101, 'unbind must not spawn or delete an external ped')
assert(HumalikeNpcEntityOwnership.State('external-1').entityOwner == 'external')

failure(exported.DespawnNpc('external-1'), 'npc_not_static')
local despawn = success(exported.DespawnNpc('static-1'))
assert(despawn.runtimeToken == nil and managed == nil)
assert(HumalikeNpcEntityOwnership.IsDespawned('static-1'))
assert(HumalikeNpcEntityOwnership.SuppressedStaticNpcIds()[1] == 'static-1')
assert(runtimeStatePublishes == 1)
invoking = 'mission-two'
failure(exported.RespawnNpc('static-1'), 'not_owner')
invoking = 'mission-one'
assert(exported.RespawnNpc('static-1').ok and managed == 101)
assert(#HumalikeNpcEntityOwnership.SuppressedStaticNpcIds() == 0)
assert(runtimeStatePublishes == 2)

assert(exported.DespawnNpc('static-1').ok)
HumalikeNpcEntityOwnership.DefinitionChanged('static-1', 'external')
assert(#HumalikeNpcEntityOwnership.SuppressedStaticNpcIds() == 0)
assert(runtimeStatePublishes == 4)

local rebound = success(exported.BindNpcEntity('external-1', 52, { routingBucket = 2 }))
exists[202] = false
HumalikeNpcEntityOwnership.Reconcile()
assert(NpcRegistry['external-1'].entity_id == nil)
failure(exported.UnbindNpcEntity(rebound.id), 'binding_not_found')

invoking = nil
failure(exported.BindNpcEntity('external-1', 52, {}), 'external_resource_required')
print('entity_ownership: ok')
