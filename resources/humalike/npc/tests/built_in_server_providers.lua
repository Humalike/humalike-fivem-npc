local handlers, exported = {}, {}
local started = { humalike = true }
local notifications, added = {}, {}

Config = {
    Integrations = {
        player = 'auto', inventory = 'auto', dispatch = 'none', actions = 'none',
    },
    SupportedActions = {},
}

local esxPlayer = {
    identifier = 'esx-fallback',
    name = 'ESX Fallback',
    job = { name = 'ambulance' },
    getIdentifier = function() return 'esx:character' end,
    getName = function() return 'Elena Sanchez' end,
    getJob = function() return { name = 'ambulance' } end,
    canCarryItem = function(item, quantity) return item == 'water' and quantity == 2 end,
    addInventoryItem = function(item, quantity, metadata)
        added.esx = { item, quantity, metadata }
    end,
    showNotification = function(message, kind)
        notifications.esx = { message, kind }
    end,
}
local qbPlayer = {
    PlayerData = {
        citizenid = 'qb:character',
        charinfo = { firstname = 'Quinn', lastname = 'Bailey' },
        job = { name = 'police', onduty = true },
    },
    Functions = {
        AddItem = function(item, quantity, _slot, metadata)
            added.qbcore = { item, quantity, metadata }
            return true
        end,
    },
}
local qboxPlayer = {
    PlayerData = {
        citizenid = 'qbox:character',
        charinfo = { firstname = 'Alex', lastname = 'Morgan' },
        job = { name = 'mechanic', onduty = false },
    },
}

local resourceExports = {
    es_extended = {
        getSharedObject = function()
            return { GetPlayerFromId = function(source) return source == 7 and esxPlayer or nil end }
        end,
    },
    ['qb-core'] = {
        GetCoreObject = function()
            return {
                Functions = {
                    GetPlayer = function(source) return source == 7 and qbPlayer or nil end,
                    Notify = function(source, message, kind)
                        notifications.qbcore = { source, message, kind }
                    end,
                },
            }
        end,
    },
    ['qb-inventory'] = {
        AddItem = function(_, source, item, quantity, _slot, metadata, reason)
            added.qbcore = { source, item, quantity, metadata, reason }
            return true
        end,
    },
    qbx_core = {
        GetPlayer = function(_, source) return source == 7 and qboxPlayer or nil end,
        Notify = function(_, source, message, kind)
            notifications.qbox = { source, message, kind }
        end,
    },
    ox_inventory = {
        AddItem = function(_, source, item, quantity, metadata)
            added.ox = { source, item, quantity, metadata }
            return item ~= 'invalid'
        end,
    },
}

function GetCurrentResourceName() return 'humalike' end
function GetInvokingResource() return nil end
function GetResourceState(resource) return started[resource] and 'started' or 'stopped' end
function GetPlayerIdentifiers() return { 'license:standalone' } end
function GetPlayerName(source) return source == 7 and 'Standalone Player' or nil end
function TriggerClientEvent() end
function AddEventHandler(name, callback) handlers[name] = callback end
function TriggerEvent(name, ...)
    if handlers[name] then handlers[name](...) end
end
exports = setmetatable(resourceExports, {
    __call = function(_, name, callback) exported[name] = callback end,
})

dofile('../integration/server/registry.lua')
dofile('../integration/server/player.lua')
dofile('../integration/server/inventory.lua')
dofile('../integration/server/dispatch.lua')
dofile('../integration/server/actions.lua')
dofile('../integration/providers/common/server.lua')
dofile('../integration/providers/standalone/server.lua')
dofile('../integration/providers/esx/server.lua')
dofile('../integration/providers/qbcore/server.lua')
dofile('../integration/providers/qbox/server.lua')
dofile('../integration/providers/ox_inventory/server.lua')
dofile('../integration/providers/qb_inventory/server.lua')

assert(HumalikePlayer.Name() == 'standalone')
assert(not HumalikeInventory.Available())

started.es_extended = true
handlers.onResourceStart('es_extended')
assert(HumalikePlayer.Name() == 'esx')
assert(HumalikePlayer.GetCharacterId(7) == 'esx:character')
assert(HumalikePlayer.GetCharacterName(7) == 'Elena Sanchez')
assert(HumalikePlayer.HasJob(7, { 'ambulance' }, true))
assert(HumalikeInventory.AddItem(7, 'water', 2, { quality = 10 }))
assert(added.esx[1] == 'water' and added.esx[3].quality == 10)
assert(HumalikePlayer.Notify(7, 'Hello', 'success'))
assert(notifications.esx[2] == 'success')

started.ox_inventory = true
handlers.onResourceStart('ox_inventory')
assert(exported.GetProviderStatus().selected.inventory.name == 'ox_inventory')
assert(HumalikeInventory.AddItem(7, 'bandage', 1, { sterile = true }))
assert(added.ox[1] == 7 and added.ox[4].sterile)

started['qb-core'] = true
started['qb-inventory'] = true
handlers.onResourceStart('qb-core')
assert(exported.GetProviderStatus().domains.player.state == 'ambiguous')

Config.Integrations.player = 'qbcore'
Config.Integrations.inventory = 'qb_inventory'
handlers.onResourceStart('test')
assert(HumalikePlayer.Name() == 'qbcore')
assert(HumalikePlayer.GetCharacterName(7) == 'Quinn Bailey')
assert(HumalikePlayer.HasJob(7, { 'police' }, true))
qbPlayer.PlayerData.job.onduty = false
assert(not HumalikePlayer.HasJob(7, { 'police' }, true))
assert(HumalikeInventory.AddItem(7, 'radio', 1, { channel = 1 }))
assert(added.qbcore[1] == 7 and added.qbcore[2] == 'radio')

Config.Integrations.player = 'auto'
Config.Integrations.inventory = 'auto'
started['qb-core'] = nil
started['qb-inventory'] = nil
handlers.onResourceStop('qb-core')
assert(HumalikePlayer.Name() == 'esx')
assert(exported.GetProviderStatus().selected.inventory.name == 'ox_inventory')

started.qbx_core = true
handlers.onResourceStart('qbx_core')
assert(exported.GetProviderStatus().domains.player.state == 'ambiguous')
Config.Integrations.player = 'qbox'
handlers.onResourceStart('test')
assert(HumalikePlayer.GetCharacterId(7) == 'qbox:character')
assert(HumalikePlayer.GetCharacterName(7) == 'Alex Morgan')
assert(not HumalikePlayer.HasJob(7, { 'mechanic' }, true))
assert(HumalikePlayer.HasJob(7, { 'mechanic' }, false))
assert(HumalikePlayer.Notify(7, 'Careful', 'warning'))
assert(notifications.qbox[3] == 'warning')

Config.Integrations.player = 'missing'
handlers.onResourceStart('test')
assert(HumalikePlayer.Name() == nil)
assert(exported.GetProviderStatus().domains.player.state == 'unavailable')

print('built_in_server_providers: ok')
