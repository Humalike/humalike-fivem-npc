local handlers = {}
local reports = {}
local originalCalls = 0
local provider = 'qbcore'

local original = setmetatable({}, {
    __call = function()
        originalCalls = originalCalls + 1
    end,
})

local core = {
    Commands = {
        List = {
            me = {
                help = 'me help',
                arguments = { { name = 'message' } },
                argsrequired = false,
                callback = original,
                permission = 'user',
            },
        },
    },
}

function core.Commands.Add(name, help, arguments, argsrequired, callback, permission)
    assert(name == 'me')
    core.Commands.List.me = {
        help = help,
        arguments = arguments,
        argsrequired = argsrequired,
        callback = callback,
        permission = permission,
    }
end

exports = {
    ['qb-core'] = {
        GetCoreObject = function(_, filters)
            assert(#filters == 1 and filters[1] == 'Commands')
            return core
        end,
    },
}

function AddEventHandler(name, callback) handlers[name] = callback end
function GetCurrentResourceName() return 'humalike' end
function GetResourceState(name)
    assert(name == 'qb-core')
    return 'started'
end
function SetTimeout(_, callback) callback() end

HumalikePlayer = { Name = function() return provider end }
HumalikeProviderUtils = {
    Callable = function(value)
        return type(value) == 'function' or type(value) == 'table'
    end,
}
function HumalikeDebug() end
function HumalikeReportPlayerEvent(playerId, event)
    reports[#reports + 1] = { playerId = playerId, event = event }
    return true
end

dofile('../integration/providers/qbcore/world_events.lua')

local wrapped = core.Commands.List.me.callback
assert(wrapped ~= original)
wrapped(7, { 'patrzy', 'na', 'zegar' }, '/me patrzy na zegar')
assert(originalCalls == 1)
assert(#reports == 1)
assert(reports[1].playerId == 7)
assert(reports[1].event.type == 'rp_action')
assert(reports[1].event.kind == 'me')
assert(reports[1].event.text == 'patrzy na zegar')

provider = 'standalone'
wrapped(7, { 'ignored' }, '/me ignored')
assert(originalCalls == 2)
assert(#reports == 1)

handlers.onResourceStop('humalike')
assert(core.Commands.List.me.callback == original)

handlers.onResourceStart('qb-core')
local replacement = function() end
core.Commands.List.me.callback = replacement
handlers.onResourceStop('humalike')
assert(core.Commands.List.me.callback == replacement)

print('qbcore_world_events: ok')
