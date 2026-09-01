local requests = {}
local responseStatus, responseBody = 200, '{}'
local runtimeAvailable = true
local bootstrapRequests = 0

GetConvar = function() return 'https://edge.example' end
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
    callback(responseStatus, responseBody, {})
end
HumaLike = {
    RuntimeCredentials = function()
        if not runtimeAvailable then return nil end
        return {
            edgeToken = 'edge-token',
            voiceToken = 'voice-token',
            voiceUrl = 'https://voice.example',
        }
    end,
    ClearRuntimeCredentials = function() runtimeAvailable = false end,
    SetStatus = function() end,
    RequestBootstrap = function() bootstrapRequests = bootstrapRequests + 1 end,
}

dofile('../server/core/http.lua')

HumaLike.PostEdgeAction('get_npc_roster', {}, function(ok, status)
    assert(ok and status == 200)
end)
assert(requests[1].body == '{}', 'empty edge payload must be a JSON object')

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

print('core_http: ok')
