local handlers, exported = {}, {}
local ready
local owner = nil
local started = { humalike = true, custom_one = true, custom_two = true }

Config = {
    Integrations = {
        player = 'auto', inventory = 'auto', dispatch = 'auto', actions = 'auto',
    },
    SupportedActions = { 'wave' },
}

function GetCurrentResourceName() return 'humalike' end
function GetInvokingResource() return owner end
function GetResourceState(resource) return started[resource] and 'started' or 'stopped' end
function GetPlayerIdentifiers() return { 'discord:1', 'license:abc' } end
function GetPlayerName(source) return source == 7 and 'Standalone Player' or nil end
function TriggerClientEvent() end
function HumalikeDebug() end
function AddEventHandler(name, callback) handlers[name] = callback end
function TriggerEvent(name, ...)
    if name == 'humalike:integration:ready' then ready = ... end
    if handlers[name] then handlers[name](...) end
end
exports = function(name, callback) exported[name] = callback end

dofile('../integration/server/registry.lua')
dofile('../integration/server/player.lua')
dofile('../integration/server/inventory.lua')
dofile('../integration/server/dispatch.lua')
dofile('../integration/server/actions.lua')
dofile('../integration/providers/standalone/server.lua')

assert(HumalikePlayer.Name() == 'standalone')
assert(HumalikePlayer.GetCharacterId(7) == 'license:abc')
assert(HumalikePlayer.GetCharacterName(7) == 'Standalone Player')
assert(HumalikePlayer.IsCharacterLoaded(7))
assert(not HumalikePlayer.HasJob(7, { 'medic' }, true))
assert(HumalikePlayer.HasJob(7, {}, true))
assert(not HumalikeInventory.Available())
assert(not HumalikeDispatch.Available())

owner = 'custom_two'
local invalid, invalidErr = exported.RegisterProvider('framework', {
    name = 'legacy', apiVersion = 1, priority = 1,
})
assert(not invalid and invalidErr == 'unknown provider domain')
invalid, invalidErr = exported.RegisterProvider('player', {
    name = 'missing_priority', apiVersion = 1,
    GetCharacterId = function() end,
    GetCharacterName = function() end,
    IsCharacterLoaded = function() return true end,
})
assert(not invalid and invalidErr == 'invalid priority')
invalid, invalidErr = exported.RegisterProvider('player', {
    name = 'UPPERCASE', apiVersion = 1, priority = 1,
    GetCharacterId = function() end,
    GetCharacterName = function() end,
    IsCharacterLoaded = function() return true end,
})
assert(not invalid and invalidErr == 'invalid provider descriptor')

owner = 'custom_one'
local characterNameCallback = setmetatable({}, {
    __call = function() return 'Custom Player' end,
})
local ok, err = exported.RegisterProvider('player', {
    name = 'custom', apiVersion = 1, priority = 50,
    GetCharacterId = function(source) return 'char-' .. source end,
    GetCharacterName = characterNameCallback,
    IsCharacterLoaded = function() return true end,
    HasJob = function(_, names, requireDuty)
        return names[1] == 'police' and requireDuty
    end,
})
assert(ok, err)
assert(HumalikePlayer.Name() == 'custom')
assert(HumalikePlayer.GetCharacterId(7) == 'char-7')
assert(HumalikePlayer.HasJob(7, { 'police' }, true))

HumalikeProviders.registered.player.custom.HasJob = function() error('job failure') end
assert(not HumalikePlayer.HasJob(7, { 'police' }, true))
assert(exported.GetProviderStatus().domains.player.state == 'degraded')
HumalikeProviders.registered.player.custom.HasJob = function() return true end
assert(HumalikePlayer.HasJob(7, { 'police' }, true))
assert(exported.GetProviderStatus().domains.player.state == 'selected')

owner = 'custom_two'
ok, err = exported.RegisterProvider('player', {
    name = 'other', apiVersion = 1, priority = 50,
    GetCharacterId = function() return 'other' end,
    GetCharacterName = function() return 'Other Player' end,
    IsCharacterLoaded = function() return true end,
})
assert(ok, err)
assert(HumalikePlayer.Name() == nil)
local ambiguous = exported.GetProviderStatus().domains.player
assert(ambiguous.state == 'ambiguous' and #ambiguous.candidates == 3)
ok, err = exported.UnregisterProvider('player', 'other')
assert(ok, err)
assert(HumalikePlayer.Name() == 'custom')

owner = 'custom_one'

ok, err = exported.RegisterProvider('inventory', {
    name = 'custom_inventory', apiVersion = 1, priority = 20,
    AddItem = function(source, item, quantity)
        return source == 7 and item == 'water' and quantity == 2
    end,
})
assert(ok, err)
assert(HumalikeInventory.Available())
assert(HumalikeInventory.AddItem(7, 'water', 2, nil))

local dispatchDependency = true
ok, err = exported.RegisterProvider('dispatch', {
    name = 'custom_dispatch', apiVersion = 1, priority = 20,
    Available = function() return dispatchDependency end,
    Report = function() return true end,
})
assert(ok, err)
assert(HumalikeDispatch.Available())
dispatchDependency = false
handlers.onResourceStop('dispatch-dependency')
assert(not HumalikeDispatch.Available())
dispatchDependency = true
handlers.onResourceStart('dispatch-dependency')
assert(HumalikeDispatch.Available())

ok, err = exported.RegisterProvider('actions', {
    name = 'custom_actions', apiVersion = 1, priority = 20,
    SupportedActions = { 'custom_action', 'custom_action' },
    RunAction = function(action) return action == 'custom_action' end,
})
assert(ok, err)
assert(HumalikeActions.Run('custom_action', 7, {}, {}))
local supported = GetSupportedActions()
assert(table.concat(supported, ',') == 'wave,give_item,custom_action')

owner = 'custom_two'
ok, err = exported.RegisterProvider('player', {
    name = 'custom', apiVersion = 1, priority = 100,
    GetCharacterId = function() end,
    GetCharacterName = function() end,
    IsCharacterLoaded = function() return true end,
})
assert(not ok and err == 'provider name already registered')

handlers.onResourceStop('custom_one')
assert(HumalikePlayer.Name() == 'standalone')
assert(not HumalikeInventory.Available())
assert(not HumalikeDispatch.Available())
assert(#HumalikeActions.Supported() == 0)

local status = exported.GetProviderStatus()
assert(status.apiVersion == 1 and status.selected.player.name == 'standalone')
assert(status.domains.player.setting == 'auto')
assert(status.domains.player.state == 'selected')

Config.Integrations.player = 'none'
handlers.onResourceStart('test')
assert(HumalikePlayer.Name() == nil)
assert(exported.GetProviderStatus().domains.player.state == 'disabled')

Config.Integrations.player = 'missing'
handlers.onResourceStart('test')
assert(HumalikePlayer.Name() == nil)
assert(exported.GetProviderStatus().domains.player.state == 'unavailable')

Config.Integrations.player = 'auto'
handlers.onResourceStart('test')
assert(HumalikePlayer.Name() == 'standalone')

handlers.onResourceStart('humalike')
assert(ready.apiVersion == 1)
assert(ready.runtimeEpoch == exported.GetProviderStatus().runtimeEpoch)

print('providers: ok')
