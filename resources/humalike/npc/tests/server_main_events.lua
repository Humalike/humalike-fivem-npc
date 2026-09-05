local handlers = {}
local commands = {}
local rosterCalls = 0
local capabilityCalls = 0
local rosterCallback
local ready
local populationUploads = 0
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
local populationOutcome = true
HumalikeNpcPopulation = {
    Upload = function(onDone)
        populationUploads = populationUploads + 1
        onDone(populationOutcome)
    end,
}
HumalikeHttp = {
    PostAction = function(name, body, callback)
        assert(name == 'report_capabilities')
        assert(body.supported_actions[1] == 'wave')
        capabilityCalls = capabilityCalls + 1
        callback(true, 200)
    end,
}
function RegisterCommand(name, handler, restricted)
    commands[name] = { handler = handler, restricted = restricted }
end

dofile('server/main.lua')

assert(commands['humalikenpc:status'].restricted == true)
assert(commands['humalikenpc:reload'].restricted == true)

assert(rosterCalls == 0 and capabilityCalls == 0 and populationUploads == 0)
populationOutcome = false
handlers['humalike:core:ready']({ generation = 2 })
assert(rosterCalls == 1 and capabilityCalls == 1 and populationUploads == 1)
populationOutcome = true
handlers['humalike:core:ready']({ generation = 3 })
assert(rosterCalls == 2 and capabilityCalls == 2 and populationUploads == 2, 'a failed upload is retried on the next ready')
assert(ready == nil)
rosterCallback(true)
assert(ready[1] == 'humalike:npc:ready')
assert(ready[2].apiVersion == 1 and ready[2].generation == 3)
handlers['humalike:core:ready']({ generation = 4 })
assert(rosterCalls == 3 and capabilityCalls == 3 and populationUploads == 2, 'a successful upload is not repeated')
