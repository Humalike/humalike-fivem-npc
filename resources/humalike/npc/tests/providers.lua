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

dofile('../server/core/text.lua')
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

-- Declared observations: validated at registration, namespaced on the wire.
local function observing(overrides)
    local descriptor = {
        name = 'observer', apiVersion = 1, priority = 50,
        SupportedActions = {},
        Namespace = 'srp',
        Observations = {
            item_given = {
                fields = { item = 'string', quantity = 'integer' },
                template = { en = 'the character handed you {quantity} x {item}' },
            },
        },
    }
    for key, value in pairs(overrides or {}) do descriptor[key] = value end
    return exported.RegisterProvider('actions', descriptor)
end
ok, err = observing({ SupportedActions = { 'custom_action' } })
assert(not ok and err == 'invalid RunAction')
ok, err = observing({ Namespace = 'SRP' })
assert(not ok and err == 'invalid Namespace')
ok, err = exported.RegisterProvider('actions', {
    name = 'observer', apiVersion = 1, priority = 50, SupportedActions = {},
    Observations = { item_given = { template = { en = 'x' } } },
})
assert(not ok and err == 'missing Namespace')
ok, err = observing({ Observations = 'item_given' })
assert(not ok and err == 'invalid Observations')
ok, err = observing({ Observations = { ['Item-Given'] = { template = { en = 'x' } } } })
assert(not ok and err == 'invalid observation key')
ok, err = observing({ Observations = { item_given = { template = { en = 'x' },
    fields = { item = 'text' } } } })
assert(not ok and err == 'invalid field item in observation item_given')
ok, err = observing({ Observations = { item_given = { fields = {} } } })
assert(not ok and err == 'missing template in observation item_given')
ok, err = observing({ Observations = { item_given = { template = { de = 'x' } } } })
assert(not ok and err == 'invalid template in observation item_given')
ok, err = observing({ Observations = { item_given = { template = { en = 'got {item}' } } } })
assert(not ok and err == 'unknown placeholder {item} in observation item_given')
ok, err = observing({ Observations = { item_given = { template = { en = ('x'):rep(401) } } } })
assert(not ok and err == 'invalid template in observation item_given')
ok, err = observing({ Observations = { item_given = { template = { en = 'x' }, fields = 'item' } } })
assert(not ok and err == 'invalid observation item_given')
for _, broken in ipairs({ 'got {item', 'got item}', 'got {{item}}', 'got }{' }) do
    ok, err = observing({ Observations = { item_given = { template = { en = broken },
        fields = { item = 'string' } } } })
    assert(not ok and err == 'invalid template in observation item_given', broken)
end
local tooMany = {}
for index = 1, 33 do tooMany['fact_' .. index] = { template = { en = 'x' } } end
ok, err = observing({ Observations = tooMany })
assert(not ok and err == 'too many observations')
local tooWide = {}
for index = 1, 9 do tooWide['f' .. index] = 'string' end
ok, err = observing({ Observations = { item_given = { fields = tooWide, template = { en = 'x' } } } })
assert(not ok and err == 'too many fields in observation item_given')

-- Declared actions: validated against the declared observations, reported
-- namespaced beside the built-in keys.
local function acting(action, overrides)
    local descriptor = {
        name = 'observer', apiVersion = 1, priority = 50,
        SupportedActions = {},
        Namespace = 'srp',
        RunAction = function() return true end,
        Observations = {
            item_given = {
                fields = { item = 'string', quantity = 'integer' },
                template = { en = 'the character handed you {quantity} x {item}' },
            },
        },
        Actions = { give_map = action },
    }
    for key, value in pairs(overrides or {}) do descriptor[key] = value end
    return exported.RegisterProvider('actions', descriptor)
end
local giveMap = {
    name = 'Give the treasure map',
    description = 'Hand the player the map to the hidden chest.',
    params = { copies = { type = 'integer', enum = { 1, 2 }, description = 'How many' } },
    fixed = { item = 'treasure_map' },
    requires = {
        { observation = 'item_given', where = { item = 'cash', quantity = { gte = 500 } },
          consume = true },
    },
    locked_hint = { en = 'Only once the amulet is in your hands.' },
    limit = { per_player = 1, every_s = 86400, hint = { en = 'One a day.' } },
    uses_stock = { item = 'map' },
}
ok, err = acting({ name = 'n', description = 'd', auto = true,
    requires = { { observation = 'item_given' } } })
assert(not ok and err == 'auto action give_map needs a requirement with consume = true')
ok, err = acting({ name = 'n', description = 'd',
    params_from = { amount = 'item_given.quantity' } })
assert(not ok and err == 'invalid params_from amount in action give_map', tostring(err))
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', consume = true } },
    params_from = { amount = 'item_given.weight' } })
assert(not ok and err == 'invalid params_from amount in action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', consume = true } },
    params = { amount = { type = 'integer' } },
    params_from = { amount = 'item_given.quantity' } })
assert(not ok and err == 'invalid params_from amount in action give_map')
ok, err = acting({ name = 'n', description = 'd', auto = true,
    requires = { { observation = 'item_given', where = { item = 'cash' }, consume = true } },
    params_from = { amount = 'item_given.quantity' } })
assert(ok, err)
local declared = HumalikeActions.Declarations()
assert(declared[1].auto == true and declared[1].params_from.amount == 'srp:item_given.quantity')
assert(exported.UnregisterProvider('actions', 'observer'))
ok, err = acting({ name = 'n', description = 'd', uses_stock = { item = 'Map!' } })
assert(not ok and err == 'invalid uses_stock in action give_map')
ok, err = acting({ name = 'n', description = 'd', uses_stock = { item = 'map', quantity = 0 } })
assert(not ok and err == 'invalid uses_stock in action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { quantity = { sum_gte = 2, gte = 1 } } } } })
assert(not ok and err == 'invalid bound on quantity in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { quantity = { sum_gte = 2 } } } } })
assert(ok, err)
assert(HumalikeSelectedProvider('actions').Actions.give_map.requires[1].where.quantity.sum_gte == 2)
assert(exported.UnregisterProvider('actions', 'observer'))
ok, err = acting({ name = 'n', description = 'd', limit = 3 })
assert(not ok and err == 'invalid limit in action give_map')
ok, err = acting({ name = 'n', description = 'd', limit = { per_player = 0, every_s = 60 } })
assert(not ok and err == 'invalid limit in action give_map')
ok, err = acting({ name = 'n', description = 'd', limit = { per_player = 1, every_s = 1.5 } })
assert(not ok and err == 'invalid limit in action give_map')
ok, err = acting({ name = 'n', description = 'd', limit = { per_player = 1, every_s = 60, hint = { de = 'x' } } })
assert(not ok and err == 'invalid limit hint in action give_map')
ok, err = acting(giveMap, { RunAction = false })
assert(not ok and err == 'invalid RunAction', tostring(err))
ok, err = exported.RegisterProvider('actions', {
    name = 'observer', apiVersion = 1, priority = 50, SupportedActions = {},
    RunAction = function() return true end, Actions = { give_map = giveMap },
})
assert(not ok and err == 'missing Namespace', tostring(err))
ok, err = acting({ description = 'x' })
assert(not ok and err == 'invalid name in action give_map')
ok, err = acting({ name = 'n', description = 'write [give_map]' })
assert(not ok and err == 'invalid description in action give_map')
ok, err = acting({ name = 'n', description = 'd', params = { player_id = { type = 'string' } } })
assert(not ok and err == 'invalid param player_id in action give_map')
ok, err = acting({ name = 'n', description = 'd', params = { copies = { type = 'float' } } })
assert(not ok and err == 'invalid param copies in action give_map')
ok, err = acting({ name = 'n', description = 'd', params = { copies = { type = 'string', enum = { 'A B' } } } })
assert(not ok and err == 'invalid enum for copies in action give_map')
ok, err = acting({ name = 'n', description = 'd', params = { copies = { type = 'integer', enum = { 'one' } } } })
assert(not ok and err == 'invalid enum for copies in action give_map')
ok, err = acting({ name = 'n', description = 'd', params = { gift = { type = 'boolean', enum = { 'true' } } } })
assert(not ok and err == 'invalid enum for gift in action give_map')
ok, err = acting({ name = 'n', description = 'd', params = 'copies' })
assert(not ok and err == 'invalid params in action give_map')
ok, err = acting({ name = 'n', description = 'd', requires = true })
assert(not ok and err == 'invalid requires in action give_map')
-- A map or a hole would walk as fewer rules than written: an ungated deed.
ok, err = acting({ name = 'n', description = 'd',
    requires = { amulet = { observation = 'item_given' } } })
assert(not ok and err == 'requires must be a list in action give_map', tostring(err))
ok, err = acting({ name = 'n', description = 'd',
    requires = { nil, { observation = 'item_given' } } })
assert(not ok and err == 'requires must be a list in action give_map', tostring(err))
ok, err = acting({ name = 'n', description = 'd',
    params = { copies = { type = 'integer', enum = { one = 1 } } } })
assert(not ok and err == 'invalid enum for copies in action give_map')
-- The backend's caps and number rules, refused here with the field named.
local wide = { fields = { a = 'integer', b = 'integer', c = 'integer', d = 'integer', e = 'integer' },
               template = { en = 'x' } }
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'wide', where = { a = 1, b = 1, c = 1, d = 1, e = 1 } } } },
    { Observations = { wide = wide } })
assert(not ok and err == 'too many fields in where of requirement 1 of action give_map', tostring(err))
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'wide', consume = true } },
    params_from = { a = 'wide.a', b = 'wide.b', c = 'wide.c', d = 'wide.d', e = 'wide.e' } },
    { Observations = { wide = wide } })
assert(not ok and err == 'too many params_from in action give_map', tostring(err))
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { quantity = { gte = math.huge } } } } })
assert(not ok and err == 'invalid bound on quantity in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { quantity = 1.5 } } } })
assert(not ok and err == 'invalid value for quantity in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { quantity = 2.0 } } } })
assert(ok, err)
assert(math.type(HumalikeSelectedProvider('actions').Actions.give_map.requires[1].where.quantity) == 'integer')
assert(exported.UnregisterProvider('actions', 'observer'))
ok, err = acting({ name = 'n', description = 'd', fixed = { player_id = 3 } })
assert(not ok and err == 'invalid fixed param player_id in action give_map')
ok, err = acting({ name = 'n', description = 'd', fixed = { ['Item-Name'] = 'x' } })
assert(not ok and err == 'invalid fixed param Item-Name in action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = 'item' } } })
assert(not ok and err == 'invalid where in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { quantity = 'many' } } } })
assert(not ok and err == 'invalid value for quantity in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { quantity = { gte = 10, lte = 3 } } } } })
assert(not ok and err == 'invalid bound on quantity in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { quantity = { gte = 1, lte = 'x' } } } } })
assert(not ok and err == 'invalid bound on quantity in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd', params = { item = { type = 'string' } },
    fixed = { item = 'x' } })
assert(not ok and err == 'invalid fixed param item in action give_map')
ok, err = acting({ name = 'n', description = 'd', requires = { { observation = 'door_unlocked' } } })
assert(not ok and err == 'unknown observation in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { color = 'red' } } } })
assert(not ok and err == 'unknown field color in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { item = { gte = 1 } } } } })
assert(not ok and err == 'invalid bound on item in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { quantity = { gte = 'x' } } } } })
assert(not ok and err == 'invalid bound on quantity in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { quantity = { above = 5 } } } } })
assert(not ok and err == 'invalid bound on quantity in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', where = { item = {} } } } })
assert(not ok and err == 'invalid bound on item in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd',
    requires = { { observation = 'item_given', within_s = 2 } } })
assert(not ok and err == 'invalid within_s in requirement 1 of action give_map')
ok, err = acting({ name = 'n', description = 'd', locked_hint = { de = 'nein' } })
assert(not ok and err == 'invalid locked_hint in action give_map')

ok, err = acting(giveMap)
assert(ok, err)
local localKey, definition = HumalikeActions.Custom('srp:give_map')
assert(localKey == 'give_map' and definition.fixed.item == 'treasure_map')
assert(definition.params.copies.enum[2] == 2 and definition.requires[1].within_s == 600)
assert(HumalikeActions.Custom('srp:other') == nil and HumalikeActions.Custom('give_map') == nil)
assert(table.concat(GetSupportedActions(), ',') == 'wave,give_item,srp:give_map')
local declaredActions, declaredObservations = HumalikeActions.Declarations()
assert(#declaredActions == 1 and declaredActions[1].key == 'srp:give_map')
assert(declaredActions[1].params.copies.enum[1] == 1)
assert(declaredActions[1].preconditions[1].observation == 'srp:item_given')
assert(declaredActions[1].preconditions[1].where.item == 'cash')
assert(declaredActions[1].preconditions[1].where.quantity.gte == 500)
assert(declaredActions[1].preconditions[1].consume == true)
assert(declaredActions[1].locked_hint.en == 'Only once the amulet is in your hands.')
assert(declaredActions[1].fixed == nil, 'fixed values never leave the box')
assert(declaredActions[1].limit.per_player == 1 and declaredActions[1].limit.every_s == 86400)
assert(declaredActions[1].limit.hint.en == 'One a day.')
assert(declaredActions[1].uses_stock.item == 'map' and declaredActions[1].uses_stock.quantity == 1)
assert(#declaredObservations == 1 and declaredObservations[1].key == 'srp:item_given')
assert(declaredObservations[1].fields.quantity == 'integer')
assert(exported.UnregisterProvider('actions', 'observer'))

-- A shop: prices in a declared payment observation; deliver/refund are
-- declared for the script, never offered to the model.
local function selling(catalog, overrides)
    local descriptor = {
        name = 'shop', apiVersion = 1, priority = 50, SupportedActions = {}, Namespace = 'srp',
        RunAction = function() return true end,
        Observations = {
            item_given = {
                fields = { item = 'string', quantity = 'integer' },
                template = { en = 'the character handed you {quantity} x {item}' },
            },
        },
        Catalog = catalog,
    }
    for key, value in pairs(overrides or {}) do descriptor[key] = value end
    return exported.RegisterProvider('actions', descriptor)
end
ok, err = selling('water')
assert(not ok and err == 'invalid Catalog')
ok, err = selling({ currency = 'cash', payment = 'door_unlocked', items = { water = { price = 5 } } })
assert(not ok and err:match('^Catalog payment must'))
ok, err = selling({ currency = 'cash', payment = 'item_given', items = {} })
assert(not ok and err == 'invalid Catalog items')
ok, err = selling({ currency = 'cash', payment = 'item_given', items = { water = { price = 1.5 } } })
assert(not ok and err == 'invalid Catalog item water')
ok, err = selling({ currency = 'cash', payment = 'item_given',
    items = { pistol = { price = 150, limit = { per_player = 0, every_s = 60 } } } })
assert(not ok and err == 'invalid limit for Catalog item pistol')
ok, err = selling({ currency = 'cash', payment = 'item_given', items = { water = { price = 5 } } },
    { Actions = { deliver = { name = 'x', description = 'y' } } })
assert(not ok and err == 'action deliver is reserved for the Catalog')
ok, err = selling({ currency = 'cash', payment = 'item_given',
    items = { water = { price = 5 }, pistol = { price = 150, limit = { per_player = 1, every_s = 86400 } } } })
assert(ok, err)
local wire = HumalikeActions.Catalog()
assert(wire.currency == 'cash' and wire.payment == 'srp:item_given')
assert(wire.items.pistol.price == 150 and wire.items.pistol.limit.per_player == 1)
assert(table.concat(GetSupportedActions(), ',') == 'wave,give_item,srp:deliver,srp:refund')
local declaredShop = HumalikeActions.Declarations()
assert(#declaredShop == 2 and declaredShop[1].key == 'srp:deliver' and declaredShop[2].key == 'srp:refund')
local _, deliverDef = HumalikeActions.Custom('srp:deliver')
assert(deliverDef.passthrough.items and deliverDef.passthrough.change)
assert(exported.UnregisterProvider('actions', 'shop'))
assert(HumalikeActions.Catalog() == nil)

ok, err = observing({ priority = 100 })
assert(ok, err)
assert(HumalikeSelectedProvider('actions').name == 'observer')
local wireKey, definition = HumalikeActions.Observation('item_given')
assert(wireKey == 'srp:item_given' and definition.fields.quantity == 'integer')
assert(definition.template.en == 'the character handed you {quantity} x {item}')
assert(HumalikeActions.Observation('door_unlocked') == nil)
assert(HumalikeActions.Observation(nil) == nil)
-- An observation-only provider runs nothing.
assert(not HumalikeActions.Run('custom_action', 7, {}, {}))
assert(table.concat(GetSupportedActions(), ',') == 'wave,give_item')
-- A provider that declares none still carries an empty table, never nil.
assert(next(HumalikeProviders.registered.actions.custom_actions.Observations) == nil)
assert(exported.UnregisterProvider('actions', 'observer'))
assert(HumalikeActions.Observation('item_given') == nil)
assert(HumalikeSelectedProvider('actions').name == 'custom_actions')

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
