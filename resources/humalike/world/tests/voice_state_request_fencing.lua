local handlers, requests, clientEvents, threads = {}, {}, {}, {}

WorldConfig = {
    voice = {
        enabled = true,
        deltaBatchIntervalMs = 100,
        snapshotIntervalMs = 60000,
    },
}
HumalikeWorldAuthority = {
    epoch = 'epoch-1',
    players = {
        [7] = {
            generation = 1,
            routingBucket = 0,
            loaded = true,
            dead = false,
            deafened = false,
        },
    },
}
RegisterNetEvent = function(name, callback) handlers[name] = callback end
AddEventHandler = function(name, callback) handlers[name] = callback end
TriggerClientEvent = function(name, target, payload)
    clientEvents[#clientEvents + 1] = { name = name, target = target, payload = payload }
end
CreateThread = function(callback)
    threads[#threads + 1] = coroutine.create(callback)
end
Wait = function() coroutine.yield() end
HumaLike = {
    RuntimeCredentials = function() return { serverId = 'server-1' } end,
    ErrorCode = function(body) return body and body.error and body.error.code or nil end,
    RequestBootstrap = function() return true end,
    PostVoice = function(path, body, callback)
        requests[#requests + 1] = { path = path, body = body, callback = callback }
    end,
}

dofile('server/voice.lua')
assert(#threads == 2)
assert(coroutine.resume(threads[1]))

handlers['humalike:core:ready']()
local abandonedSnapshot = requests[1]
assert(abandonedSnapshot.path == '/v1/fivem/state')
handlers['humalike:runtime:refreshed']({ voiceChanged = false })
local replacementSnapshot = requests[2]
assert(replacementSnapshot.path == '/v1/fivem/state')

source = 7
handlers['humalike:world:requestVoiceSession']()
requests[3].callback(200, {
    sessionId = 'session-1',
    ticket = 'ticket-1',
    controlUrl = 'wss://voice.example',
})
assert(#clientEvents == 1 and clientEvents[1].name == 'humalike:world:voiceSessionReady')

abandonedSnapshot.callback(204)
assert(coroutine.resume(threads[1]))
assert(#requests == 3,
    'an abandoned snapshot callback must not unlock a current state request')

replacementSnapshot.callback(204)
assert(coroutine.resume(threads[1]))
assert(#requests == 4 and requests[4].body.mode == 'delta',
    'pending state must publish after the current snapshot completes')

print('voice_state_request_fencing: ok')
