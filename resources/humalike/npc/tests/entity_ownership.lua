local exported, handlers, events, invalidations = {}, {}, {}, {}
local invoking = 'mission-one'
local deleted = {}
local exists = { [101] = true, [202] = true, [303] = true, [404] = true, [505] = true }
local networkEntities = { [52] = 202, [53] = 303, [54] = 404, [55] = 505 }
local types = { [101] = 1, [202] = 1, [303] = 2, [404] = 1, [505] = 1 }
local models = { [101] = 10, [202] = 10, [303] = 10, [404] = 10, [505] = 11 }
local buckets = { [101] = 0, [202] = 2, [303] = 2, [404] = 2, [505] = 2 }
local states = {}
local managed = 101

NpcRegistry = {
    ['static-1'] = {
        npc_id = 'static-1', model = 'model-one', entity_id = 101,
        network_id = 51, runtime_token = 'managed-token',
    },
}
HumaLike = { RuntimeCredentials = function() return { bootId = 'boot-1' } end }

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
function RemovePersistentNpc()
    if managed then deleted[managed] = true end
    managed = nil
end
function RemovePersistentNpcRuntimeBinding(npcId, token)
    invalidations[#invalidations + 1] = { npcId = npcId, token = token }
end
function PreparePersistentNpcEntity(entry, entity)
    states[entity] = states[entity] or {}
    states[entity].humalike_npc_id = entry.npc_id
    states[entity].humalike_npc_kind = 'persistent'
end
function RegisterPersistentNpcBinding(entry, entity)
    entry.runtime_token = ('token-%d'):format(entity)
    HumalikeNpcEntityOwnership.SetRuntimeToken(entry.npc_id, entity, entry.runtime_token)
end
function EnsurePersistentNpc(entry)
    managed = 101
    exists[101] = true
    entry.entity_id, entry.network_id, entry.runtime_token = 101, 51, 'restored-token'
    return 101
end

dofile('server/entity_ownership.lua')

local _, vehicleError = exported.BindNpcEntity('static-1', 53, { routingBucket = 2 })
assert(vehicleError == 'entity_not_ped')
local _, playerError = exported.BindNpcEntity('static-1', 54, { routingBucket = 2 })
assert(playerError == 'player_ped_not_allowed')
local _, modelError = exported.BindNpcEntity('static-1', 55, { routingBucket = 2 })
assert(modelError == 'model_mismatch')
local _, bucketError = exported.BindNpcEntity('static-1', 52, { routingBucket = 0 })
assert(bucketError == 'routing_bucket_mismatch')

local binding = assert(exported.BindNpcEntity('static-1', 52, { routingBucket = 2 }))
assert(binding.ownerResource == 'mission-one' and binding.networkId == 52)
assert(deleted[101] and managed == nil)
assert(states[202].humalike_npc_id == 'static-1')
assert(NpcRegistry['static-1'].entity_id == 202)
assert(invalidations[1].token == 'managed-token')
assert(HumalikeNpcEntityOwnership.State('static-1').entityOwner == 'external')
assert(exported.BindNpcEntity('static-1', 52, {}).id == binding.id)

local _, conflict = exported.DespawnNpc('static-1')
assert(conflict == 'npc_externally_bound')
invoking = 'mission-two'
assert(exported.UnbindNpcEntity(binding.id) == false)
invoking = 'mission-one'
assert(exported.UnbindNpcEntity(binding.id) == true)
assert(states[202].humalike_npc_id == nil and exists[202])
assert(managed == 101 and NpcRegistry['static-1'].entity_id == 101)

local despawn = assert(exported.DespawnNpc('static-1'))
assert(despawn.ownerResource == 'mission-one' and managed == nil)
assert(HumalikeNpcEntityOwnership.IsDespawned('static-1'))
assert(exported.DespawnNpc('static-1').id == despawn.id)
invoking = 'mission-two'
assert(exported.RespawnNpc('static-1') == false)
invoking = 'mission-one'
assert(exported.RespawnNpc('static-1') == true and managed == 101)

local rebound = assert(exported.BindNpcEntity('static-1', 52, { routingBucket = 2 }))
exists[202] = false
HumalikeNpcEntityOwnership.Reconcile()
assert(managed == 101 and HumalikeNpcEntityOwnership.State('static-1').entityOwner == 'humalike')
assert(exported.UnbindNpcEntity(rebound.id) == false)

assert(exported.DespawnNpc('static-1'))
handlers.onResourceStop('mission-one')
assert(managed == 101 and not HumalikeNpcEntityOwnership.IsDespawned('static-1'))

invoking = nil
local _, ownerError = exported.BindNpcEntity('static-1', 52, {})
assert(ownerError == 'external_resource_required')

print('entity_ownership: ok')
