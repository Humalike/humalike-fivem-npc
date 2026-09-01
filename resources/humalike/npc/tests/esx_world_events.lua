local handlers = {}
local reports = {}
local provider = 'esx'
local rpchatState = 'started'
local gameTimer = 1000
source = 7

function RegisterNetEvent(name, callback)
    handlers[name] = callback
end

function AddEventHandler(name, callback)
    handlers[name] = callback
end

function GetGameTimer()
    return gameTimer
end

function GetResourceState(name)
    assert(name == 'esx_rpchat')
    return rpchatState
end

HumalikePlayer = { Name = function() return provider end }

function HumalikeReportPlayerEvent(playerId, event)
    reports[#reports + 1] = { playerId = playerId, event = event }
    return true
end

dofile('../integration/providers/esx/world_events.lua')

local handler = handlers['humalike:integration:esx:rpAction']
handler('me', 'spogląda na zegarek')
assert(#reports == 1)
assert(reports[1].playerId == 7)
assert(reports[1].event.kind == 'me')

handler('me', 'spamuje')
assert(#reports == 1)
gameTimer = gameTimer + 500
handler('do', 'jest późno')
assert(#reports == 2)

handlers.playerDropped()
handler('me', 'wraca')
assert(#reports == 3)

provider = 'standalone'
handler('do', 'jest późno')
rpchatState = 'stopped'
provider = 'esx'
handler('do', 'jest późno')
assert(#reports == 3)

print('esx_world_events: ok')
