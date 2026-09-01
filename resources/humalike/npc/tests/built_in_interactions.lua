local handlers, exported, events = {}, {}, {}
local started = {}
local oxCalls, qbCalls = {}, {}

Config = {
    Integrations = { interaction = 'auto' },
    AmbientControl = { InteractionDistance = 4.0 },
}
AmbientInteractionAdapters = {}

local resourceExports = {
    ox_target = {
        addLocalEntity = function(_, entity, options)
            oxCalls.add = { entity, options }
        end,
        removeLocalEntity = function(_, entity, names)
            oxCalls.remove = { entity, names }
        end,
    },
    ['qb-target'] = {
        AddTargetEntity = function(_, entity, data)
            qbCalls.add = { entity, data }
        end,
        RemoveTargetEntity = function(_, entity, labels)
            qbCalls.remove = { entity, labels }
        end,
    },
}

function GetCurrentResourceName() return 'humalike' end
function GetInvokingResource() return nil end
function GetResourceState(resource) return started[resource] and 'started' or 'stopped' end
function GetGameTimer() return 100 end
function DoesEntityExist(entity) return entity == 42 end
function CreateThread() end
function AddEventHandler(name, callback) handlers[name] = callback end
function TriggerEvent(name, ...)
    events[#events + 1] = { name, ... }
    if handlers[name] then handlers[name](...) end
end
exports = setmetatable(resourceExports, {
    __call = function(_, name, callback) exported[name] = callback end,
})

dofile('../integration/client/interactions.lua')
dofile('../integration/providers/builtin/client.lua')
dofile('../integration/providers/ox_target/client.lua')
dofile('../integration/providers/qb_target/client.lua')

local selectedEntity
local options = {
    {
        text = 'Help', icon = 'kit-medical',
        canInteract = function(entity) return entity == 42 end,
        onSelect = function(entity) selectedEntity = entity end,
    },
}

assert(HumalikeInteractionAdapter().name == 'builtin')

started.ox_target = true
handlers.onClientResourceStart('ox_target')
local ox = HumalikeInteractionAdapter()
assert(ox.name == 'ox_target')
assert(HumalikeInteractionAdd(ox, 'test', 42, options))
assert(oxCalls.add[1] == 42 and oxCalls.add[2][1].name == 'test:1')
oxCalls.add[2][1].onSelect(42)
assert(selectedEntity == 42)
HumalikeInteractionRemove(ox, 'test')
assert(oxCalls.remove[2][1] == 'test:1')

started['qb-target'] = true
handlers.onClientResourceStart('qb-target')
assert(HumalikeInteractionAdapter() == nil)
assert(exported.GetInteractionProviderStatus().state == 'ambiguous')

Config.Integrations.interaction = 'qb-target'
handlers.onClientResourceStart('test')
local qb = HumalikeInteractionAdapter()
assert(qb.name == 'qb-target')
assert(HumalikeInteractionAdd(qb, 'test', 42, options))
assert(qbCalls.add[1] == 42 and qbCalls.add[2].distance == 4.0)
assert(qbCalls.add[2].options[1].icon == 'fas fa-kit-medical')
qbCalls.add[2].options[1].action(42)
assert(selectedEntity == 42)
HumalikeInteractionRemove(qb, 'test')
assert(qbCalls.remove[2][1] == 'Help')

Config.Integrations.interaction = 'auto'
started['qb-target'] = nil
handlers.onClientResourceStop('qb-target')
assert(HumalikeInteractionAdapter().name == 'ox_target')

Config.Integrations.interaction = 'missing'
handlers.onClientResourceStart('test')
assert(HumalikeInteractionAdapter() == nil)
assert(exported.GetInteractionProviderStatus().state == 'unavailable')

print('built_in_interactions: ok')
