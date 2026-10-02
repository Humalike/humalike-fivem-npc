local nodeCalls, fallbackCalls, timers = {}, {}, {}
local nodeAvailable = true

GetConvar = function() return 'https://npc.example' end
json = {
    encode = function(value)
        if type(value) == 'table' and next(value) == nil then return '[]' end
        return '{"value":1}'
    end,
    decode = function(body) return { raw = body } end,
}
GetCurrentResourceName = function() return 'humalike' end
CreateThread = function(fn) fn() end
SetTimeout = function(ms, fn) timers[#timers + 1] = { ms = ms, fn = fn } end
PerformHttpRequest = function(url, callback, method, body, headers)
    fallbackCalls[#fallbackCalls + 1] = { url = url, callback = callback,
        method = method, body = body, headers = headers }
end
local resource = {
    humalikeNodeHttpRequest = function(self, id, url, method, body, headers, callback)
        assert(self ~= nil)
        if not nodeAvailable then error('No such export humalikeNodeHttpRequest') end
        nodeCalls[#nodeCalls + 1] = { id = id, url = url, method = method,
            body = body, headers = headers, callback = callback }
    end,
}
exports = setmetatable({}, { __index = function(_, name)
    assert(name == 'humalike')
    return resource
end })
HumaLike = {
    RuntimeCredentials = function()
        return { edgeToken = 'edge-token', edgeUrl = 'https://edge-a.example',
            voiceToken = 'voice-token', voiceUrl = 'https://voice.example' }
    end,
    EdgeAssignmentKey = function() return 'edge-a:7' end,
    IsCurrentEdgeAssignment = function() return true end,
    VoiceAssignmentKey = function() return 'voice-a:4' end,
    IsCurrentVoiceAssignment = function() return true end,
}

dofile('../server/core/http.lua')

-- Node path: same URL, method, body encoding and headers as before.
local calls = {}
HumaLike.EdgeRequest('get_npc_roster', 'token-1', {}, function(status, body, headers, err)
    calls[#calls + 1] = { status = status, body = body, headers = headers, err = err }
end)
assert(#nodeCalls == 1 and #fallbackCalls == 0, 'requests must go through Node')
local first = nodeCalls[1]
assert(first.url == 'https://npc.example/v1/npc/actions/get_npc_roster')
assert(first.method == 'POST' and first.body == '{}')
assert(first.headers.Authorization == 'Bearer token-1')
assert(first.headers['Content-Type'] == 'application/json')
assert(#timers == 1 and timers[1].ms > 30000, 'Lua timeout must outlast Node timeout')
first.callback(200, '{"ok":true}', { ['content-type'] = 'application/json' }, nil)
assert(#calls == 1 and calls[1].status == 200 and calls[1].body.raw == '{"ok":true}')
assert(calls[1].headers['content-type'] == 'application/json')
first.callback(500, '{}', {}, nil)
timers[1].fn()
assert(#calls == 1, 'callback must run exactly once')

-- Lua timeout: a lost response resolves with status 0 and a late one is ignored.
local timeoutCalls = {}
HumaLike.PostVoice('/v1/fivem/state', { value = 1 }, function(status, body)
    timeoutCalls[#timeoutCalls + 1] = { status = status, body = body }
end)
assert(#nodeCalls == 2 and nodeCalls[2].url == 'https://voice.example/v1/fivem/state')
assert(nodeCalls[2].body == '{"value":1}')
assert(nodeCalls[2].headers.Authorization == 'Bearer voice-token')
timers[2].fn()
assert(#timeoutCalls == 1 and timeoutCalls[1].status == 0 and timeoutCalls[1].body == nil)
nodeCalls[2].callback(200, '{}', {}, nil)
assert(#timeoutCalls == 1, 'responses for unknown ids must be ignored')

-- Network failure reported by Node keeps PerformHttpRequest semantics.
local failure
HumaLike.EdgeRequest('get_npc_roster', 'token-1', {}, function(status, body, _, err)
    failure = { status = status, body = body, err = err }
end)
nodeCalls[3].callback(0, nil, {}, 'ECONNREFUSED')
assert(failure.status == 0 and failure.body == nil and failure.err == 'ECONNREFUSED')
assert(nodeCalls[3].id ~= nodeCalls[1].id, 'request ids must be unique')

-- Fallback: without the Node export, PerformHttpRequest is used unchanged.
nodeAvailable = false
local fallbackResult = {}
HumaLike.EdgeRequest('get_npc_roster', 'token-2', {}, function(status, body)
    fallbackResult[#fallbackResult + 1] = { status = status, body = body }
end)
assert(#fallbackCalls == 1 and #timers == 3, 'fallback must not arm a Node timeout')
local fallback = fallbackCalls[1]
assert(fallback.url == 'https://npc.example/v1/npc/actions/get_npc_roster')
assert(fallback.method == 'POST' and fallback.body == '{}')
assert(fallback.headers.Authorization == 'Bearer token-2')
fallback.callback(200, '{}', {})
assert(#fallbackResult == 1 and fallbackResult[1].status == 200)

print('core_http_node: ok')
