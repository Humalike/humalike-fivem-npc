local requests = {}
local responseStatus, responseBody = 200, '{}'
local runtimeAvailable = true
local bootstrapRequests = 0
local currentAssignment = 'edge-a:7'
local currentVoiceAssignment = 'voice-a:4'
local deferredHttp

GetConvar = function(name)
    assert(name == 'humalike_control_plane_url')
    return 'https://npc.example'
end
json = {
    encode = function(value)
        if type(value) == 'table' and next(value) == nil then return '[]' end
        return '{"value":1}'
    end,
    decode = function() return {} end,
}
PerformHttpRequest = function(url, callback, method, body, headers)
    requests[#requests + 1] = {
        url = url,
        method = method,
        body = body,
        headers = headers,
    }
    if deferredHttp ~= nil then
        deferredHttp = callback
        return
    end
    callback(responseStatus, responseBody, {})
end
HumaLike = {
    RuntimeCredentials = function()
        if not runtimeAvailable then return nil end
        return {
            edgeToken = 'edge-token',
            edgeUrl = 'https://edge-a.example',
            voiceToken = 'voice-token',
            voiceUrl = 'https://voice.example',
        }
    end,
    ClearRuntimeCredentials = function() runtimeAvailable = false end,
    InvalidateRuntimeCredentials = function() runtimeAvailable = false end,
    SetStatus = function() end,
    RequestBootstrap = function() bootstrapRequests = bootstrapRequests + 1 end,
    EdgeAssignmentKey = function() return currentAssignment end,
    IsCurrentEdgeAssignment = function(expected) return expected == currentAssignment end,
    VoiceAssignmentKey = function() return currentVoiceAssignment end,
    IsCurrentVoiceAssignment = function(expected)
        return expected == currentVoiceAssignment
    end,
}

dofile('../server/core/http.lua')

HumaLike.PostEdgeAction('get_npc_roster', {}, function(ok, status)
    assert(ok and status == 200)
end)
assert(requests[1].body == '{}', 'empty edge payload must be a JSON object')
assert(requests[1].url == 'https://edge-a.example/v1/npc/actions/get_npc_roster',
    'stateful edge actions must use the assigned node endpoint')

HumaLike.PostVoice('/v1/fivem/empty', {}, function(status)
    assert(status == 200)
end)
assert(requests[2].body == '{}', 'empty voice payload must be a JSON object')

HumaLike.PostEdgeAction('report_capabilities', { value = 1 })
assert(requests[3].body == '{"value":1}', 'non-empty payload must use the JSON encoder')

responseStatus = 403
responseBody = '{"error":{"code":"ACTION_FORBIDDEN"}}'
json.decode = function()
    return { error = { code = 'ACTION_FORBIDDEN' } }
end
HumaLike.PostEdgeAction('upsert_npc_runtime_binding', { value = 1 })
assert(bootstrapRequests == 0, 'domain authorization errors must not rotate runtime credentials')

responseStatus = 401
responseBody = '{"error":{"code":"UNAUTHORIZED"}}'
json.decode = function()
    return { error = { code = 'UNAUTHORIZED' } }
end
HumaLike.PostEdgeAction('get_npc_roster', {})
assert(bootstrapRequests == 1 and not runtimeAvailable,
    'runtime identity rejection must request exactly one bootstrap')

runtimeAvailable = true
responseStatus = 409
responseBody = '{"error":{"code":"EDGE_ASSIGNMENT_STALE"}}'
json.decode = function()
    return { error = { code = 'EDGE_ASSIGNMENT_STALE' } }
end
HumaLike.PostEdgeAction('get_npc_roster', {})
assert(bootstrapRequests == 2 and not runtimeAvailable,
    'stale edge generation must invalidate credentials and request one bootstrap')

for _, code in ipairs({
    'EDGE_ASSIGNMENT_NOT_READY', 'EDGE_WRONG_OWNER', 'EDGE_ASSIGNMENT_STALE'
}) do
    assert(HumaLike.IsEdgeAssignmentError(409, { error = { code = code } }))
end
assert(not HumaLike.IsEdgeAssignmentError(403,
    { error = { code = 'EDGE_WRONG_OWNER' } }))
for _, code in ipairs({ 'assignment_not_ready', 'assignment_stale' }) do
    assert(HumaLike.IsVoiceAssignmentError(409, { error = { code = code } }))
end
assert(not HumaLike.IsVoiceAssignmentError(401,
    { error = { code = 'assignment_stale' } }))

runtimeAvailable = true
responseStatus = 200
responseBody = '{}'
deferredHttp = false
local staleResult
HumaLike.PostEdgeAction('get_npc_roster', {}, function(ok, status, body)
    staleResult = { ok = ok, status = status, body = body }
end)
local oldResponse = deferredHttp
currentAssignment = 'edge-b:8'
deferredHttp = nil
oldResponse(200, '{}', {})
assert(staleResult.ok == false and staleResult.status == 409)
assert(HumaLike.ErrorCode(staleResult.body) == 'EDGE_ASSIGNMENT_CHANGED',
    'an old edge response must be rejected before reaching domain state')

deferredHttp = false
local staleVoiceResult
HumaLike.PostVoice('/v1/fivem/state', {}, function(status, body)
    staleVoiceResult = { status = status, body = body }
end)
local oldVoiceResponse = deferredHttp
currentVoiceAssignment = 'voice-b:5'
deferredHttp = nil
oldVoiceResponse(204, '', {})
assert(staleVoiceResult == nil,
    'an old voice response must not reach domain state')

deferredHttp = false
local staleVoiceRejection
HumaLike.PostVoice('/v1/fivem/sessions', {}, function(status)
    staleVoiceRejection = status
end)
local oldVoiceRejection = deferredHttp
currentVoiceAssignment = 'voice-c:6'
deferredHttp = nil
oldVoiceRejection(401, '{"error":{"code":"UNAUTHORIZED"}}', {})
assert(staleVoiceRejection == nil,
    'an old voice rejection must not reach domain state')
local requestsBeforeCurrentVoice = #requests
local currentVoiceStatus
responseStatus = 204
responseBody = ''
HumaLike.PostVoice('/v1/fivem/sessions', {}, function(status)
    currentVoiceStatus = status
end)
assert(#requests == requestsBeforeCurrentVoice + 1 and currentVoiceStatus == 204,
    'an old voice rejection must not throttle the current assignment')

responseStatus = 401
responseBody = '{"error":{"code":"UNAUTHORIZED"}}'
local rejectedCurrentStatus
HumaLike.PostVoice('/v1/fivem/sessions', {}, function(status)
    rejectedCurrentStatus = status
end)
assert(rejectedCurrentStatus == 401)
currentVoiceAssignment = 'voice-d:7'
responseStatus = 204
responseBody = ''
local requestsBeforeReassignedVoice = #requests
local reassignedVoiceStatus
HumaLike.PostVoice('/v1/fivem/sessions', {}, function(status)
    reassignedVoiceStatus = status
end)
assert(#requests == requestsBeforeReassignedVoice + 1 and reassignedVoiceStatus == 204,
    'a new voice assignment must not inherit the old assignment cooldown')

responseStatus = 409
responseBody = '{"error":{"code":"assignment_stale"}}'
json.decode = function()
    return { error = { code = 'assignment_stale' } }
end
local bootstrapBeforeStaleVoice = bootstrapRequests
HumaLike.PostVoice('/v1/fivem/state', {})
assert(bootstrapRequests == bootstrapBeforeStaleVoice + 1,
    'a stale voice assignment must request fresh runtime credentials')

HumaLike.EdgeRequest('bootstrap_fivem_runtime', 'license', {}, function() end)
assert(requests[#requests].url ==
    'https://npc.example/v1/npc/actions/bootstrap_fivem_runtime',
    'bootstrap discovery must use the stable control plane')

print('core_http: ok')
