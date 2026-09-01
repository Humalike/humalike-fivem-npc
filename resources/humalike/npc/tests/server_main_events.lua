local handlers = {}
local commands = {}
local rosterCalls = 0
local capabilityCalls = 0
source = 7

function AddEventHandler(name, handler)
    handlers[name] = handler
end
function CreateThread() end
function print() end

function RegisterNetEvent() end
function SyncNpcRoster(_, repair)
    rosterCalls = rosterCalls + 1
    assert(repair == true)
end
function GetSupportedActions() return { 'wave' } end
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

assert(rosterCalls == 0 and capabilityCalls == 0)
handlers['humalike:core:ready']()
assert(rosterCalls == 1 and capabilityCalls == 1)
