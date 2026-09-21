local handlers, requests, clientEvents, timeouts = {}, {}, {}, {}
local decoded = {}
local bootstrapRequests = 0
local bootstrapAccepted = true

WorldConfig = {
    voice = {
        enabled = true,
        deltaBatchIntervalMs = 100, snapshotIntervalMs = 60000,
    },
}
HumalikeWorldAuthority = {
    epoch = 'epoch-1',
    players = {
        [7] = {
            generation = 1, routingBucket = 0, loaded = true, dead = false, deafened = false,
        },
        [8] = {
            generation = 1, routingBucket = 0, loaded = true, dead = false, deafened = false,
        },
    },
}
json = {
    encode = function() return '{}' end,
    decode = function(body) return decoded[body] end,
}
PerformHttpRequest = function(url, callback, method, body)
    requests[#requests + 1] = { url = url, callback = callback, method = method, body = body }
end
RegisterNetEvent = function(name, callback) if callback then handlers[name] = callback end end
AddEventHandler = function(name, callback) handlers[name] = callback end
TriggerClientEvent = function(name, target, payload)
    clientEvents[#clientEvents + 1] = { name = name, target = target, payload = payload }
end
CreateThread = function() end
Wait = function() end
SetTimeout = function(delay, callback)
    timeouts[#timeouts + 1] = { delay = delay, callback = callback }
end
HumaLike = {
    RuntimeCredentials = function() return { serverId = 'server-1' } end,
    ErrorCode = function(body) return body and body.error and body.error.code or nil end,
    RequestBootstrap = function(reason, attempt, immediate)
        bootstrapRequests = bootstrapRequests + 1
        assert((reason == 'voice assignment_stale' or reason == 'voice assignment_not_ready')
            and attempt == 1 and immediate)
        return bootstrapAccepted
    end,
    PostVoice = function(path, body, callback)
        requests[#requests + 1] = { url = 'https://voice.example' .. path,
            callback = function(status, encoded) callback(status, decoded[encoded]) end,
            method = 'POST', body = body }
    end,
}

dofile('server/voice.lua')

source = 7
handlers['humalike:world:requestVoiceSession']()
assert(#requests == 1 and requests[1].url:match('/v1/fivem/sessions$'))
decoded.ready = {
    sessionId = 'session-1', ticket = 'ticket-1', controlUrl = 'wss://voice.example',
}
requests[1].callback(200, 'ready')
assert(#clientEvents == 1 and clientEvents[1].name == 'humalike:world:voiceSessionReady')
handlers['humalike:world:requestVoiceSession']()
source = 8
handlers['humalike:world:requestVoiceSession']()
local oldRuntimeRequest = requests[3]
decoded.stale = { error = { code = 'assignment_stale' } }
requests[2].callback(409, 'stale')
assert(bootstrapRequests == 1 and #clientEvents == 1)
source = 7
handlers['humalike:world:requestVoiceSession']()
assert(#requests == 3, 'session retried before runtime refresh completed')
handlers['humalike:core:ready']()
assert(#requests == 6)
oldRuntimeRequest.callback(200, 'ready')
assert(#clientEvents == 1, 'old runtime response was accepted after refresh')
decoded.reassigned = {
    sessionId = 'session-2', ticket = 'ticket-2', controlUrl = 'wss://voice-b.example',
}
local reassignedRequest
for index = 4, 6 do
    if requests[index].body and requests[index].body.playerId == '7' then
        reassignedRequest = requests[index]
    end
end
assert(reassignedRequest, 'player session was not retried after runtime refresh')
reassignedRequest.callback(200, 'reassigned')
assert(#clientEvents == 2 and clientEvents[2].payload.controlUrl == 'wss://voice-b.example')

-- A response minted for an older authority generation is rejected.
source = 7
handlers['humalike:world:requestVoiceSession']()
local authorityRequest = requests[#requests]
HumalikeWorldAuthority.players[7].generation = 2
authorityRequest.callback(200, 'ready')
assert(#clientEvents == 3)
assert(clientEvents[3].name == 'humalike:world:voiceSessionFailed')
assert(clientEvents[3].payload == 409)
handlers['humalike:world:requestVoiceSession']()
local droppedPlayerRequest = requests[#requests]
handlers['humalike:world:authorityChanged']({ kind = 'remove', playerId = '7' })
HumalikeWorldAuthority.players[7] = nil
droppedPlayerRequest.callback(200, 'ready')
assert(#clientEvents == 3)

source = 8
handlers['humalike:world:requestVoiceSession']()
local abandonedSameAssignmentRequest = requests[#requests]
local beforeSameAssignmentRecovery = #requests
handlers['humalike:runtime:refreshed']({ voiceChanged = false })
assert(#requests == beforeSameAssignmentRecovery + 2,
    'same-assignment credential recovery must replay state and pending sessions')
abandonedSameAssignmentRequest.callback(200, 'ready')
assert(#clientEvents == 3,
    'a callback abandoned during credential recovery must remain fenced')

local beforeVoiceMove = #requests
handlers['humalike:runtime:voiceChanged']()
assert(clientEvents[#clientEvents].name == 'humalike:world:voiceReconnect'
    and clientEvents[#clientEvents].target == 8,
    'voice assignment change must reconnect connected players')
assert(#requests == beforeVoiceMove + 1
    and requests[#requests].url:match('/v1/fivem/state$')
    and requests[#requests].body.mode == 'snapshot',
    'voice assignment change must replay authoritative state to the new node')

source = 8
handlers['humalike:world:requestVoiceSession']()
decoded.notReady = { error = { code = 'assignment_not_ready' } }
bootstrapAccepted = false
requests[#requests].callback(409, 'notReady')
assert(bootstrapRequests == 2, 'assignment_not_ready must refresh runtime immediately')
assert(timeouts[#timeouts].delay == 15000,
    'an assignment refresh must have a bounded wait')
timeouts[#timeouts].callback()
assert(clientEvents[#clientEvents].name == 'humalike:world:voiceSessionFailed'
    and clientEvents[#clientEvents].target == 8
    and clientEvents[#clientEvents].payload == 503,
    'a rejected assignment refresh must release the waiting client')

print('server_voice: ok')
