local handlers, requests, timers = {}, {}, {}
local assignment = 'edge-a:7'

HumaLike = {
    RuntimeCredentials = function()
        if assignment == nil then return nil end
        return { bootId = 'fivem-boot', edgeAssignmentKey = assignment }
    end,
    EdgeAssignmentKey = function()
        return assignment
    end,
    IsCurrentEdgeAssignment = function(expected)
        return expected == assignment
    end,
}
HumalikeNpcRuntimeControl = {
    EdgeControls = function() return { ['npc-1'] = { action = 'wave' } } end,
}
HumalikeNpcEntityOwnership = {
    SuppressedStaticNpcIds = function() return { 'npc-2' } end,
}
HumalikeHttp = {
    PostAction = function(name, body, callback)
        requests[#requests + 1] = { name = name, body = body, callback = callback }
    end,
}
function AddEventHandler(name, callback) handlers[name] = callback end
function SetTimeout(delay, callback)
    timers[#timers + 1] = { delay = delay, callback = callback }
end

dofile('server/runtime_state.lua')

handlers['humalike:core:ready']()
assert(#requests == 1 and requests[1].name == 'sync_npc_runtime_state')
assert(requests[1].body.suppressed_static_npc_ids[1] == 'npc-2')

assignment = 'edge-b:8'
handlers['humalike:runtime:edgeChanged']({ generation = 8 })
assert(#requests == 1, 'the replacement snapshot queues behind the old request')
requests[1].callback(true, 200, {})
assert(#requests == 2, 'the old response must cause a snapshot for the new assignment')
assert(requests[2].body.controls['npc-1'].action == 'wave')
requests[2].callback(true, 200, {})
assert(#timers == 0, 'a current successful snapshot must not retry')

HumalikeNpcRuntimeState.Sync()
local rejectedRequest = requests[3]
assignment = nil
rejectedRequest.callback(false, 401, {})
assert(#requests == 3, 'runtime state waits while credentials are unavailable')
assignment = 'edge-b:8'
handlers['humalike:runtime:refreshed']()
assert(#requests == 4,
    'same-assignment credential recovery must replay the pending runtime snapshot')
requests[4].callback(true, 200, {})

print('runtime_state_replay: ok')
