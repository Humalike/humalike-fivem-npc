local handlers, requests, clientEvents = {}, {}, {}
local decoded = {}

WorldConfig = {
    voice = {
        enabled = true, apiBaseUrl = 'https://voice.example', serverId = 'server-1',
        deltaBatchIntervalMs = 100, snapshotIntervalMs = 60000,
    },
}
HumalikeWorldAuthority = {
    epoch = 'epoch-1',
    players = {
        [7] = {
            generation = 1, routingBucket = 0, loaded = true, dead = false, deafened = false,
        },
    },
}
GetConvar = function(name) return name == 'humalike_voice_server_secret' and 'secret' or '' end
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
HumaLike = {
    RuntimeCredentials = function() return { serverId = 'server-1' } end,
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
assert(#requests == 2)
HumalikeWorldAuthority.players[7].generation = 2
requests[2].callback(200, 'ready')
assert(#clientEvents == 2)
assert(clientEvents[2].name == 'humalike:world:voiceSessionFailed')
assert(clientEvents[2].payload == 409)
handlers['humalike:world:requestVoiceSession']()
assert(#requests == 3)
handlers['humalike:world:authorityChanged']({ kind = 'remove', playerId = '7' })
HumalikeWorldAuthority.players[7] = nil
requests[3].callback(200, 'ready')
assert(#clientEvents == 2)

print('server_voice: ok')
