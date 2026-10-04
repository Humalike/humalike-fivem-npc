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
AmbientPedNpcIds = { [20] = 'ambient' }

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
AmbientPedNpcIds[20] = 'ambient-2'
registerCalls = 0
handlers['humalike:npc:ambientPedAssigned'](
    'ambient-2', 20, AmbientNpcEntries['ambient-2'])
assert(registerCalls == 1 and registered['ambient-2'])

-- The periodic pass pauses every few NPCs. While it is parked a lease can go
-- and others can bind: the pass must survive that (a table is never walked
-- across the pause) and must not undo a registration made meanwhile.
local function lease(index)
    local npcId, ped = ('crowd-%02d'):format(index), 100 + index
    entities[ped] = true
    AmbientNpcEntries[npcId] = { entity_id = 1000 + index, network_id = ped + 200, lease_token = 'lease-' .. index }
    AmbientPeds[npcId], AmbientPedNpcIds[ped] = ped, npcId
    return npcId, ped
end
local function drop(npcId)
    local ped = AmbientPeds[npcId]
    AmbientNpcEntries[npcId], AmbientPeds[npcId], AmbientPedNpcIds[ped] = nil, nil, nil
    handlers['humalike:npc:ambientPedRemoved'](npcId)
end
for index = 1, 20 do lease(index) end
handlers['humalike:world:registrationRequested']()
for index = 1, 20 do assert(registered[('crowd-%02d'):format(index)], 'the crowd is registered') end

for round = 1, 40 do
    local parked = 0
    function Wait(ms)
        if ms ~= 0 then error('stop') end
        parked = parked + 1
        coroutine.yield()
    end
    local pass = coroutine.create(threads[1])
    assert(coroutine.resume(pass))
    assert(parked == 1, 'the pass pauses after a slice of the crowd')
    -- While parked: one lease goes, a batch binds (enough to make the tables grow).
    drop(('crowd-%02d'):format((round % 20) + 1))
    local bound = {}
    for index = 1, 12 do
        local npcId, ped = lease(1000 + round * 20 + index)
        handlers['humalike:npc:ambientPedAssigned'](npcId, ped, AmbientNpcEntries[npcId])
        bound[#bound + 1] = npcId
    end
    while coroutine.status(pass) == 'suspended' do
        local ok, failure = coroutine.resume(pass)
        assert(ok or tostring(failure):find('stop', 1, true), 'the pass died: ' .. tostring(failure))
    end
    for _, npcId in ipairs(bound) do
        assert(registered[npcId], 'a lease bound while the pass was parked stays registered')
    end
    for _, npcId in ipairs(bound) do drop(npcId) end
    lease((round % 20) + 1)
    handlers['humalike:world:registrationRequested']()
end
function Wait() error('stop') end

print('world: ok')
