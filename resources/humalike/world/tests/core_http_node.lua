local nodeCalls, fallbackCalls, timers = {}, {}, {}
local nodeAvailable = true
local printed = {}
local realPrint = print
print = function(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printed[#printed + 1] = table.concat(parts, ' ')
end

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
    humalikeNodeHttpRequest = function(self, id, url, method, body, headers, timeoutMs, callback)
        assert(self ~= nil)
        if not nodeAvailable then error('humalikeNodeHttpRequest is private to this resource') end
        nodeCalls[#nodeCalls + 1] = { id = id, url = url, method = method,
            body = body, headers = headers, timeoutMs = timeoutMs, callback = callback }
    end,
}
local exportLookups = 0
exports = setmetatable({}, { __index = function(_, name)
    assert(name == 'humalike')
    exportLookups = exportLookups + 1
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
assert(first.timeoutMs == 30000, 'ordinary actions use the default limit')
assert(#timers == 1 and timers[1].ms > first.timeoutMs, 'Lua timeout must outlast Node timeout')
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
assert(nodeCalls[2].timeoutMs == 120000, 'voice state sync uses the long limit')
assert(timers[2].ms > nodeCalls[2].timeoutMs)
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

-- Bootstrap and runtime-state syncs get the long limit; the Lua timer still
-- outlasts it. Other voice paths keep the default.
for _, action in ipairs({ 'bootstrap_fivem_runtime', 'sync_npc_runtime_state',
    'sync_player_sessions' }) do
    HumaLike.EdgeRequest(action, 'token-1', {}, function() end)
    local call = nodeCalls[#nodeCalls]
    assert(call.url == 'https://npc.example/v1/npc/actions/' .. action)
    assert(call.timeoutMs == 120000, action .. ' must use the long limit')
    assert(timers[#timers].ms > call.timeoutMs, action .. ' Lua timer must outlast Node')
end
HumaLike.PostVoice('/v1/fivem/sessions', {}, function() end)
assert(nodeCalls[#nodeCalls].timeoutMs == 30000)
assert(exportLookups == 1, 'the export is resolved once and reused')

-- Fallback: without the Node export, PerformHttpRequest is used unchanged.
nodeAvailable = false
local fallbackResult = {}
HumaLike.EdgeRequest('get_npc_roster', 'token-2', {}, function(status, body)
    fallbackResult[#fallbackResult + 1] = { status = status, body = body }
end)
local timersBefore = #timers
local fallbackResult2 = {}
HumaLike.EdgeRequest('get_npc_roster', 'token-2', {}, function(status)
    fallbackResult2[#fallbackResult2 + 1] = status
end)
assert(#fallbackCalls == 2 and #timers == timersBefore, 'fallback must not arm a Node timeout')
local warnings = {}
for _, line in ipairs(printed) do
    if line:find('node_http_unavailable', 1, true) then warnings[#warnings + 1] = line end
end
assert(#warnings == 1, 'fallback warning is logged once')
assert(warnings[1]:find('private to this resource', 1, true),
    'fallback warning must carry the underlying error: ' .. warnings[1])
local fallback = fallbackCalls[1]
assert(fallback.url == 'https://npc.example/v1/npc/actions/get_npc_roster')
assert(fallback.method == 'POST' and fallback.body == '{}')
assert(fallback.headers.Authorization == 'Bearer token-2')
fallback.callback(200, '{}', {})
assert(#fallbackResult == 1 and fallbackResult[1].status == 200)

print = realPrint
print('core_http_node: ok')
