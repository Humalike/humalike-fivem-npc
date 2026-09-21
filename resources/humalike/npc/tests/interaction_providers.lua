local handlers, exported, events = {}, {}, {}
local owner = 'adapter_one'
local timer = 100

Config = { Integrations = { interaction = 'auto' } }
AmbientInteractionAdapters = {
    builtin = {
        name = 'builtin',
        priority = -1000,
        Add = function() return true end,
        Remove = function() end,
    },
}

function GetCurrentResourceName() return 'humalike' end
function GetInvokingResource() return owner end
function GetGameTimer() return timer end
function GetResourceState() return 'started' end
function AddEventHandler(name, callback) handlers[name] = callback end
function TriggerEvent(name, ...)
    events[#events + 1] = { name, ... }
    if handlers[name] then handlers[name](...) end
end
exports = function(name, callback) exported[name] = callback end

dofile('../integration/client/interactions.lua')

local progress = setmetatable({}, { __call = function() return true end })
local ok, err = exported.RegisterInteractionProvider({
    name = 'custom', apiVersion = 1, priority = 100,
    Add = function() return true end,
    Remove = function() end,
    Progress = progress,
})
assert(ok, err)
assert(HumalikeInteractionAdapter().name == 'custom')
assert(HumalikeInteractionProgress(10, 'test') == true)

AmbientInteractionAdapters.custom.Add = function() error('add failure') end
assert(not HumalikeInteractionAdd(AmbientInteractionAdapters.custom, 'id', 42, {}))
assert(exported.GetInteractionProviderStatus().state == 'degraded')
AmbientInteractionAdapters.custom.Add = function() return true end
assert(HumalikeInteractionAdd(AmbientInteractionAdapters.custom, 'id', 42, {}))
assert(exported.GetInteractionProviderStatus().state == 'selected')

owner = 'adapter_two'
ok, err = exported.RegisterInteractionProvider({
    name = 'other', apiVersion = 1, priority = 100,
    Add = function() return true end,
    Remove = function() end,
})
assert(ok, err)
assert(HumalikeInteractionAdapter() == nil)
assert(exported.GetInteractionProviderStatus().state == 'ambiguous')

handlers.onClientResourceStop('adapter_two')
assert(HumalikeInteractionAdapter().name == 'custom')

owner = 'adapter_one'
ok, err = exported.UnregisterInteractionProvider('custom')
assert(ok, err)
assert(HumalikeInteractionAdapter().name == 'builtin')

handlers.onClientResourceStart('humalike')
local ready = events[#events]
assert(ready[1] == 'humalike:integration:ready')
assert(ready[2].apiVersion == 1)
assert(ready[2].runtimeEpoch == exported.GetInteractionProviderStatus().runtimeEpoch)

assert(exported.GetInteractionProviderStatus().settingsSource == 'local')
HumalikeSettings = { applied = true }
HumalikeConvars = { overrides = {} }
assert(exported.GetInteractionProviderStatus().settingsSource == 'default')
HumalikeConvars.overrides.humalike_interaction = 'builtin'
assert(exported.GetInteractionProviderStatus().settingsSource == 'server')

print('interaction_providers: ok')
