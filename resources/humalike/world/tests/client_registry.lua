GetInvokingResource = function() return 'humalike' end

dofile('client/contracts.lua')
dofile('client/registry.lua')

local function registration(id, entity)
    return {
        npcId = id,
        entity = entity,
        entityId = entity + 100,
        networkId = entity + 200,
        modelHash = 123,
        runtimeToken = 'token-' .. id,
        kind = 'persistent',
        ownerResource = 'humalike',
    }
end

local ok, reason = HumalikeWorldRegistry.Register(registration('npc-1', 10))
assert(ok, reason)
assert(HumalikeWorldRegistry.Count() == 1)
assert(HumalikeWorldRegistry.revision == 1)
assert(HumalikeWorldRegistry.entries['npc-1'].generation == 1)
assert(HumalikeWorldRegistry.Register(registration('npc-1', 10)))
assert(HumalikeWorldRegistry.revision == 1)
assert(HumalikeWorldRegistry.entries['npc-1'].generation == 1)

assert(HumalikeWorldRegistry.Update('npc-1', { activity = 'talking' }))
assert(HumalikeWorldRegistry.entries['npc-1'].generation == 2)
assert(HumalikeWorldRegistry.revision == 2)
assert(HumalikeWorldRegistry.Update('npc-1', { activity = 'talking' }))
assert(HumalikeWorldRegistry.revision == 2)
assert(not HumalikeWorldRegistry.Update('npc-1', { activity = 'idle' }, 'other-resource'))
assert(HumalikeWorldRegistry.entries['npc-1'].activity == 'talking')

assert(HumalikeWorldRegistry.Register(registration('npc-2', 20)))
HumalikeWorldRegistry.entries['npc-2'].ownerResource = 'another-resource'
assert(HumalikeWorldRegistry.RemoveOwner('humalike') == 1)
assert(HumalikeWorldRegistry.entries['npc-1'] == nil)
assert(HumalikeWorldRegistry.entries['npc-2'] ~= nil)

local invalid = registration('', 1)
assert(not HumalikeWorldRegistry.Register(invalid))
assert(HumalikeWorldRegistry.Count() == 1)

print('client_registry: ok')
