local handlers, requests, clientEvents = {}, {}, {}
local responses = {}
local assignment = 'edge-a:7'

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
    EdgeAssignmentKey = function() return assignment end,
    IsCurrentEdgeAssignment = function(expected) return expected == assignment end,
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
assert(clientEvents[#clientEvents].name == 'humalike:world:npcEdgeReconnect'
    and clientEvents[#clientEvents].target == 7,
    'edge assignment change must reconnect edge clients only')

source = 7
handlers['humalike:world:requestNpcEdgeTicket']('boot-stale')
local staleSessionRequest = requests[#requests]
assignment = 'edge-c:9'
handlers['humalike:runtime:edgeChanged']()
local currentSyncRequest = requests[#requests]
handlers['humalike:world:requestNpcEdgeTicket']('boot-stale')
local currentSessionRequest = requests[#requests]
responses.stale = { ok = true }
staleSessionRequest.callback(200, 'stale')
assert(requests[#requests] == currentSessionRequest,
    'an old assignment response must not advance a current ticket request')
currentSyncRequest.callback(200, 'upserted')
currentSessionRequest.callback(200, 'upserted')
local staleTicketRequest = requests[#requests]
local eventsBeforeStaleTicket = #clientEvents
assignment = 'edge-d:10'
handlers['humalike:runtime:edgeChanged']()
handlers['humalike:world:requestNpcEdgeTicket']('boot-stale')
local replacementSessionRequest = requests[#requests]
replacementSessionRequest.callback(200, 'upserted')
local replacementTicketRequest = requests[#requests]
staleTicketRequest.callback(200, 'ticket')
assert(#clientEvents == eventsBeforeStaleTicket + 1,
    'an old ticket response must not be delivered after assignment change')
replacementTicketRequest.callback(200, 'ticket')
assert(#clientEvents == eventsBeforeStaleTicket + 2,
    'the current assignment ticket must still be delivered')

handlers['humalike:world:requestNpcEdgeTicket']('boot-recovered')
local rejectedSessionRequest = requests[#requests]
assignment = nil
rejectedSessionRequest.callback(401, 'missing')
assignment = 'edge-d:10'
handlers['humalike:runtime:refreshed']()
local requestsBeforeRecovery = #requests
handlers['humalike:world:requestNpcEdgeTicket']('boot-recovered')
assert(#requests == requestsBeforeRecovery + 1,
    'same-assignment credential recovery must unblock a rejected ticket request')
local recoveredSessionRequest = requests[#requests]
recoveredSessionRequest.callback(200, 'upserted')
local staleRecoveredTicket = requests[#requests]
handlers['humalike:runtime:refreshed']({ edgeChanged = false })
handlers['humalike:world:requestNpcEdgeTicket']('boot-recovered')
local replacementRecoveredSession = requests[#requests]
replacementRecoveredSession.callback(200, 'upserted')
local currentRecoveredTicket = requests[#requests]
local eventsBeforeRecoveredTicket = #clientEvents
staleRecoveredTicket.callback(200, 'ticket')
assert(#clientEvents == eventsBeforeRecoveredTicket,
    'an old ticket callback must not match a replacement on the same assignment')
currentRecoveredTicket.callback(200, 'ticket')
assert(#clientEvents == eventsBeforeRecoveredTicket + 1)
local requestsBeforeEmptySnapshot = #requests
HumalikeWorldAuthority.players = {}
handlers['humalike:world:authoritySnapshot']({})
assert(#requests == requestsBeforeEmptySnapshot,
    'empty authority must not sync and evict live sessions')

print('server_npc_edge: ok')
