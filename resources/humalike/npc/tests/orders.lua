-- PlaceOrder: the menu's lines, checked against the catalogue, posted as an
-- order request for HumaLike to price.
local exported, posted = {}, {}
local catalog
function exports(name, callback) exported[name] = callback end
function HumalikeDebug() end
HumalikePlayer = { IsCharacterLoaded = function(playerId) return playerId == 7 end }
HumalikeActions = { Catalog = function() return catalog end }
function HumalikePostPlayerEvent(playerId, event) posted[#posted + 1] = { playerId, event } end
function HumalikeObservationTarget(npcId)
    if npcId == 'npc-en' then return { language = 'en' } end
    if npcId == 'ambient-1' then return { language = 'pl', lease_token = 'lease-1' } end
    return nil, 'npc_not_found'
end

dofile('../server/core/export_result.lua')
dofile('server/orders.lua')

local place = exported.PlaceOrder
assert(place('npc-en', 7, { water = 2 }).error == 'no_catalog')
catalog = { currency = 'money', payment = 'srp:item_given',
            items = { water = { price = 5 }, burger = { price = 12 } } }
assert(place('npc-en', 0, { water = 2 }).error == 'invalid_player')
assert(place('npc-en', 8, { water = 2 }).error == 'character_not_loaded')
assert(place('npc-missing', 7, { water = 2 }).error == 'npc_not_found')
assert(place('npc-en', 7, {}).error == 'invalid_lines')
assert(place('npc-en', 7, { bread = 1 }).error == 'unknown_item:bread')
assert(place('npc-en', 7, { water = 0 }).error == 'invalid_quantity:water')
assert(place('npc-en', 7, { water = 1.5 }).error == 'invalid_quantity:water')
assert(place('npc-en', 7, { water = '2' }).error == 'invalid_quantity:water')
assert(#posted == 0)
-- A whole number is a whole number, float or not, like a reported field.
local order = place('ambient-1', 7, { water = 2.0, burger = 1 })
assert(order.ok and order.value.lines.water == 2, order.error)
assert(math.type(order.value.lines.water) == 'integer')
local event = posted[1][2]
assert(event.type == 'order_requested' and event.npc_id == 'ambient-1')
assert(event.lease_token == 'lease-1' and event.lines.burger == 1)

print('orders: ok')
