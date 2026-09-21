local handlers = {}
local commands = {}
local rosterCalls = 0
local capabilityCalls = 0
local rosterCallback
local ready
source = 7

function AddEventHandler(name, handler)
    handlers[name] = handler
end
function TriggerEvent(name, payload)
    ready = { name, payload }
end
function CreateThread() end
function print() end

function RegisterNetEvent() end
function SyncNpcRoster(callback, repair)
    rosterCalls = rosterCalls + 1
    assert(repair == true)
    rosterCallback = callback
end
function GetSupportedActions() return { 'wave' } end
HumalikeActions = { Declarations = function() return {}, {} end, Catalog = function() return nil end }
local capabilityOk = true
local lastFeatures
HumalikeHttp = {
    PostAction = function(name, body, callback)
        assert(name == 'report_capabilities')
        assert(body.supported_actions[1] == 'wave')
        lastFeatures = body.features
        capabilityCalls = capabilityCalls + 1
        callback(capabilityOk, capabilityOk and 200 or 500)
    end,
    DescribeFailure = function(status) return 'HTTP ' .. tostring(status) end,
}
function RegisterCommand(name, handler, restricted)
    commands[name] = { handler = handler, restricted = restricted }
end

dofile('server/main.lua')

assert(commands['humalikenpc:status'].restricted == true)
assert(commands['humalikenpc:reload'].restricted == true)

assert(rosterCalls == 0 and capabilityCalls == 0)
handlers['humalike:core:ready']({ generation = 3 })
assert(rosterCalls == 1 and capabilityCalls == 1)
assert(ready == nil)
rosterCallback(true)
assert(ready[1] == 'humalike:npc:ready')
assert(ready[2].apiVersion == 1 and ready[2].generation == 3)

handlers['humalike:runtime:edgeChanged']({ generation = 4 })
assert(rosterCalls == 2, 'a new edge assignment must replay the roster')
assert(capabilityCalls == 2, 'a new edge assignment must replay capabilities')

handlers['humalike:runtime:refreshed']({ edgeChanged = true })
assert(rosterCalls == 2 and capabilityCalls == 2,
    'an edge change must not be replayed twice by the refresh event')
handlers['humalike:runtime:refreshed']({ edgeChanged = false })
assert(rosterCalls == 3 and capabilityCalls == 3,
    'credential recovery must replay edge state even when the assignment is unchanged')
assert(lastFeatures == nil, 'without the population module no features are reported')

local posted, reported = 0, {}
HumalikeNpcPopulation = {
    Features = function() return { 'npc_vehicles' } end,
    CapabilitiesPosted = function() posted = posted + 1 end,
    CapabilitiesReported = function(features, ok) reported[#reported + 1] = { features, ok } end,
}
HumalikeNpcReportCapabilities()
assert(capabilityCalls == 4 and lastFeatures[1] == 'npc_vehicles', 'the population features ride along')
assert(posted == 1 and #reported == 1 and reported[1][1][1] == 'npc_vehicles' and reported[1][2] == true)
capabilityOk = false
handlers['humalike:runtime:edgeChanged']({ generation = 5 })
assert(posted == 2 and #reported == 2 and reported[2][2] == false, 'a failed post is reported as such')
