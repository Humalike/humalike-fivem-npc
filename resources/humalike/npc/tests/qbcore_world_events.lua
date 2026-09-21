local handlers = {}
local reports = {}
local provider = 'qbcore'
local coreState = 'started'
local gameTimer = 1000
source = 7

function RegisterNetEvent(name, callback) handlers[name] = callback end
function AddEventHandler(name, callback) handlers[name] = callback end
function GetGameTimer() return gameTimer end
function GetResourceState(name)
    assert(name == 'qb-core')
    return coreState
end

HumalikePlayer = { Name = function() return provider end }
function HumalikeReportPlayerEvent(playerId, event)
    reports[#reports + 1] = { playerId = playerId, event = event }
    return true
end

dofile('../integration/providers/common/server.lua')
dofile('../integration/providers/qbcore/world_events.lua')

local handler = handlers['humalike:integration:qbcore:rpAction']
handler('patrzy na zegar')
assert(#reports == 1)
assert(reports[1].playerId == 7)
assert(reports[1].event.type == 'rp_action')
assert(reports[1].event.kind == 'me')
assert(reports[1].event.text == 'patrzy na zegar')

handler('spamuje')
assert(#reports == 1, 'a second report inside 500 ms is dropped')
gameTimer = 1600
handler('  ~r~kolor~s~ <b>tag</b> zdjęty  ')
assert(#reports == 2 and reports[2].event.text == 'kolor tag zdjęty', 'markup is stripped')
gameTimer = 2200
handler('   ')
handler(42)
assert(#reports == 2, 'empty or non-string text is ignored')

provider = 'standalone'
handler('ignored')
assert(#reports == 2, 'only the qbcore player provider reports')
provider = 'qbcore'
coreState = 'stopped'
handler('ignored')
assert(#reports == 2, 'a stopped qb-core reports nothing')
coreState = 'started'

handlers.playerDropped()
gameTimer = 2300
handler('po powrocie')
assert(#reports == 3, 'a dropped player forgets its throttle')

print('qbcore_world_events: ok')
