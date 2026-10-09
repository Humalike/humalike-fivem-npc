local handlers, serverEvents = {}, {}

AddEventHandler = function(name, callback) handlers[name] = callback end
RegisterNetEvent = function(name, callback) handlers[name] = callback end
TriggerServerEvent = function(name, body)
    serverEvents[#serverEvents + 1] = { name = name, body = body }
end
HumalikeWorldContracts = { Copy = function(value) return value end }
HumalikeWorldCollector = {
    latest = { vehicle = { networkId = 777, seat = 1 } },
    Subscribe = function(kind, callback) handlers['collector:' .. kind] = callback end,
}

dofile('client/cabins.lua')

handlers['collector:motion']({ vehicle = nil })
assert(#serverEvents == 1 and serverEvents[1].body == nil)
handlers['collector:motion']({ vehicle = nil })
assert(#serverEvents == 1)
handlers['collector:motion']({ vehicle = { networkId = 501, seat = -1 } })
assert(#serverEvents == 2 and serverEvents[2].body.networkId == 501)
handlers['collector:motion']({ vehicle = { networkId = 501, seat = -1 } })
assert(#serverEvents == 2)
handlers['collector:motion']({ vehicle = { networkId = 501, seat = 0 } })
assert(#serverEvents == 3 and serverEvents[3].body.seat == 0)
handlers['humalike:world:requestCabinState']()
assert(#serverEvents == 4 and serverEvents[4].body.networkId == 777)

handlers['humalike:world:cabinMembership']({
    epoch = 'epoch-1', revision = 1, membership = { id = 'cabin-1' },
})
assert(HumalikeWorldCabin.membership.id == 'cabin-1')
print('client_cabins: ok')
