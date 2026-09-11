local handlers, threads = {}, {}
local registered, unregistered = {}, {}
local registerCalls = 0
local entities = { [10] = true, [20] = true }
local ambientTag = 'ambient'

KnownNpcs = {
    persistent = {
        entity_id = 110, network_id = 210, runtime_token = 'persistent-token',
    },
}
LoadedPeds = { persistent = 10 }
AmbientNpcEntries = {
    ambient = {
        entity_id = 120, network_id = 220, lease_token = 'lease-token',
    },
}
AmbientPeds = { ambient = 20 }

function ResolveNpcPed(npcId) return LoadedPeds[npcId] or AmbientPeds[npcId] end
function DoesEntityExist(entity) return entities[entity] == true end
function NetworkGetEntityIsNetworked() return true end
function NetworkGetNetworkIdFromEntity(entity) return entity + 200 end
function NetworkDoesEntityExistWithNetworkId() return true end
function NetworkGetEntityFromNetworkId(networkId) return networkId - 200 end
function GetEntityModel(entity) return entity == 10 and -2084633992 or 123 end
function Entity(entity)
    return { state = { humalike_runtime_token = entity == 10 and 'persistent-token' or nil,
        humalike_position_reporter = 999,
        humalike_npc_id = entity == 20 and ambientTag or nil } }
end
function AddEventHandler(name, callback) handlers[name] = callback end
function CreateThread(callback) threads[#threads + 1] = callback end
function Wait() error('stop') end

exports = setmetatable({}, {
    __index = function(_, resource)
        assert(resource == 'humalike')
        return {
            RegisterNpc = function(_, value)
                registerCalls = registerCalls + 1
                registered[value.npcId] = value
                return true
            end,
            UnregisterNpc = function(_, npcId)
                unregistered[#unregistered + 1] = npcId
                registered[npcId] = nil
                return true
            end,
        }
    end,
})

dofile('client/world.lua')
pcall(threads[1])

assert(registered.persistent and registered.persistent.kind == 'persistent')
assert(registered.ambient and registered.ambient.kind == 'ambient')
assert(registerCalls == 2)
assert(registered.persistent.modelHash == 2210333304)
assert(Entity(10).state.humalike_position_reporter == 999)

entities[10] = false
pcall(threads[1])
assert(registered.persistent == nil and unregistered[#unregistered] == 'persistent')

entities[10] = true
handlers['humalike:world:registrationRequested']()
assert(registered.persistent and registered.ambient)

handlers['humalike:npc:ambientPedRemoved']('ambient')
assert(registered.ambient == nil)
AmbientNpcEntries['ambient-2'] = {
    entity_id = 121, network_id = 220, lease_token = 'lease-token-2',
}
AmbientPeds['ambient-2'] = 20
AmbientNpcEntries.ambient = nil
ambientTag = 'ambient-2'
registerCalls = 0
handlers['humalike:npc:ambientPedAssigned'](
    'ambient-2', 20, AmbientNpcEntries['ambient-2'])
assert(registerCalls == 1 and registered['ambient-2'])

print('world: ok')
