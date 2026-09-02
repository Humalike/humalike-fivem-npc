local handlers, requests, clientEvents = {}, {}, {}
local responses = {}

WorldConfig = { npcEdge = { enabled = true } }
HumalikeWorldAuthority = {
    epoch = 'epoch-1',
    players = {
        [7] = {
            characterId = 'char-7', name = 'Player', routingBucket = 3,
            metadata = { npc = { appearance = { model = 123 } } },
        },
    },
}
HumalikeWorldDebug = function() end
GetConvar = function(name)
    if name == 'humalike_npc_service_url' then return 'https://npc.example' end
    if name == 'humalike_npc_api_key' then return 'secret' end
    return ''
end
json = {
    encode = function(value)
        if type(value) == 'table' and value.players and next(value.players) == nil then
            return '{"players":[]}'
        end
        if type(value) ~= 'table' then return tostring(value) end
        local keys, parts = {}, {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. '=' .. json.encode(value[key]) end
        return '{' .. table.concat(parts, ',') .. '}'
    end,
    decode = function(body) return responses[body] end,
}
PerformHttpRequest = function(url, callback, method, body)
    requests[#requests + 1] = { url = url, callback = callback, method = method, body = body }
end
RegisterNetEvent = function(name, callback) if callback then handlers[name] = callback end end
AddEventHandler = function(name, callback) handlers[name] = callback end
TriggerClientEvent = function(name, target, payload, bootId)
    clientEvents[#clientEvents + 1] = { name = name, target = target, payload = payload, bootId = bootId }
end
HumaLike = {
    ErrorCode = function(body)
        return body and body.error and body.error.code or nil
    end,
    PostEdgeAction = function(name, payload, callback)
        requests[#requests + 1] = {
            url = 'https://npc.example/' .. name,
            method = 'POST', body = payload,
            callback = function(status, encoded)
                callback(status >= 200 and status < 300, status, responses[encoded])
            end,
        }
    end,
}

dofile('server/npc_edge.lua')

source = 7
handlers['humalike:world:requestNpcEdgeTicket']('boot-1')
assert(#requests == 1 and requests[1].url:match('upsert_player_session$'))
responses.upserted = { ok = true }
requests[1].callback(200, 'upserted')
assert(#requests == 2 and requests[2].url:match('create_world_stream_ticket$'))
responses.ticket = { ticket = 'once', stream_url = 'wss://edge.example' }
requests[2].callback(200, 'ticket')
assert(#clientEvents == 1 and clientEvents[1].bootId == 'boot-1')
handlers['humalike:world:requestNpcEdgeTicket']('boot-2')
assert(#requests == 3 and requests[3].url:match('create_world_stream_ticket$'))
responses.missing = { error = { code = 'PLAYER_SESSION_UNKNOWN' } }
requests[3].callback(409, 'missing')
assert(#requests == 4 and requests[4].url:match('upsert_player_session$'))
requests[4].callback(200, 'upserted')
assert(#requests == 5 and requests[5].url:match('create_world_stream_ticket$'))
requests[5].callback(200, 'ticket')
assert(#clientEvents == 2 and clientEvents[2].bootId == 'boot-2')
HumalikeWorldAuthority.players[7].routingBucket = 8
handlers['humalike:world:authorityChanged']({ kind = 'upsert', playerId = '7' })
assert(#requests == 6 and requests[6].url:match('upsert_player_session$'))
requests[6].callback(200, 'upserted')
handlers['humalike:core:ready']()
assert(#requests == 7 and requests[7].url:match('sync_player_sessions$'))
handlers['humalike:runtime:edgeChanged']()
assert(#requests == 8 and requests[8].url:match('sync_player_sessions$'))
HumalikeWorldAuthority.players = {}
handlers['humalike:world:authoritySnapshot']({})
assert(#requests == 8, 'empty authority must not sync and evict live sessions')

print('server_npc_edge: ok')
