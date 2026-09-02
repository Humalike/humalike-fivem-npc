local pendingTickets = {}
local confirmedSessions = {}
local sessionRequests = {}
local syncRevision = 0

local function postAction(name, payload, callback)
    HumaLike.PostEdgeAction(name, payload, callback)
end

local function appearance(state)
    local metadata = state and state.metadata
    local npc = type(metadata) == 'table' and metadata.npc or nil
    return type(npc) == 'table' and npc.appearance or nil
end

local function sessionProjection(playerId, state)
    return {
        fivem_session_id = tonumber(playerId),
        character_id = state.characterId,
        name = state.name,
        routing_bucket = state.routingBucket,
        appearance = appearance(state),
    }
end

local function finishSessionRequests(playerId, ok, state)
    local callbacks = sessionRequests[playerId] and sessionRequests[playerId].callbacks or {}
    sessionRequests[playerId] = nil
    for _, callback in ipairs(callbacks) do callback(ok, state) end
end

local function ensureSession(playerId, callback)
    local state = HumalikeWorldAuthority.players[playerId]
    if not state then callback(false, nil) return end
    local encoded = json.encode(sessionProjection(playerId, state))
    if confirmedSessions[playerId] == encoded then callback(true, state) return end
    local pending = sessionRequests[playerId]
    if pending then
        pending.callbacks[#pending.callbacks + 1] = callback
        return
    end
    sessionRequests[playerId] = { callbacks = { callback } }
    postAction('upsert_player_session', sessionProjection(playerId, state), function(ok)
        local current = HumalikeWorldAuthority.players[playerId]
        if not current then finishSessionRequests(playerId, false, nil) return end
        local currentEncoded = json.encode(sessionProjection(playerId, current))
        if ok and currentEncoded == encoded then
            confirmedSessions[playerId] = encoded
            finishSessionRequests(playerId, true, current)
        elseif ok then
            local callbacks = sessionRequests[playerId].callbacks
            sessionRequests[playerId] = nil
            for _, waiting in ipairs(callbacks) do ensureSession(playerId, waiting) end
        else
            finishSessionRequests(playerId, false, current)
        end
    end)
end

local function syncAll()
    local players = {}
    local sentEncodings = {}
    for playerId, state in pairs(HumalikeWorldAuthority.players) do
        local projected = sessionProjection(playerId, state)
        projected.fivem_session_id = nil
        players[tostring(playerId)] = projected
        sentEncodings[playerId] = json.encode(sessionProjection(playerId, state))
    end
    if next(players) == nil then
        HumalikeWorldDebug('NPC-edge session sync skipped -- authority empty')
        return
    end
    syncRevision = syncRevision + 1
    postAction('sync_player_sessions', {
        resource_instance_id = HumalikeWorldAuthority.epoch,
        revision = syncRevision,
        players = players,
    }, function(ok, status)
        if ok then
            for playerId, encoded in pairs(sentEncodings) do
                local current = HumalikeWorldAuthority.players[playerId]
                if current and json.encode(sessionProjection(playerId, current)) == encoded then
                    confirmedSessions[playerId] = encoded
                end
            end
        else
            HumalikeWorldDebug('NPC-edge session snapshot failed status=%s', status)
        end
    end)
end

local function resetEdgeBindings()
    for playerId in pairs(sessionRequests) do
        finishSessionRequests(playerId, false, HumalikeWorldAuthority.players[playerId])
    end
    confirmedSessions = {}
    sessionRequests = {}
    pendingTickets = {}
    syncAll()
end

local function issueTicket(playerId, clientBootId, requestKey, repaired)
    ensureSession(playerId, function(ready, confirmed)
        if not pendingTickets[requestKey] then return end
        local current = HumalikeWorldAuthority.players[playerId]
        if not ready or not confirmed or not current
            or current.characterId ~= confirmed.characterId then
            pendingTickets[requestKey] = nil
            return
        end
        postAction('create_world_stream_ticket', {
            fivem_session_id = playerId,
            character_id = confirmed.characterId,
            client_boot_id = clientBootId,
        }, function(ok, status, body)
            if not pendingTickets[requestKey] then return end
            if not ok and not repaired and status == 409
                and HumaLike.ErrorCode(body) == 'PLAYER_SESSION_UNKNOWN' then
                confirmedSessions[playerId] = nil
                issueTicket(playerId, clientBootId, requestKey, true)
                return
            end
            pendingTickets[requestKey] = nil
            local latest = HumalikeWorldAuthority.players[playerId]
            if ok and body and latest and latest.characterId == confirmed.characterId then
                TriggerClientEvent('humalike:world:npcEdgeTicket',
                    playerId, body, clientBootId)
            else
                HumalikeWorldDebug('NPC-edge ticket failed player=%s status=%s',
                    playerId, status)
            end
        end)
    end)
end

RegisterNetEvent('humalike:world:requestNpcEdgeTicket', function(clientBootId)
    local playerId = tonumber(source)
    local authority = playerId and HumalikeWorldAuthority.players[playerId]
    if not authority or type(clientBootId) ~= 'string' or #clientBootId > 64 then return end
    local requestKey = tostring(playerId) .. ':' .. clientBootId
    if pendingTickets[requestKey] then return end
    pendingTickets[requestKey] = true
    issueTicket(playerId, clientBootId, requestKey, false)
end)

AddEventHandler('humalike:world:authorityChanged', function(delta)
    local playerId = tonumber(delta.playerId)
    if delta.kind == 'remove' then
        confirmedSessions[playerId] = nil
        sessionRequests[playerId] = nil
        return
    end
    confirmedSessions[playerId] = nil
    ensureSession(playerId, function() end)
end)

AddEventHandler('humalike:world:authoritySnapshot', function() syncAll() end)

AddEventHandler('humalike:core:ready', function()
    resetEdgeBindings()
end)

AddEventHandler('humalike:runtime:edgeChanged', function()
    resetEdgeBindings()
    for playerId in pairs(HumalikeWorldAuthority.players) do
        TriggerClientEvent('humalike:world:npcEdgeReconnect', playerId)
    end
end)

AddEventHandler('playerDropped', function()
    local prefix = tostring(source) .. ':'
    for key in pairs(pendingTickets) do
        if key:sub(1, #prefix) == prefix then pendingTickets[key] = nil end
    end
    confirmedSessions[tonumber(source)] = nil
    sessionRequests[tonumber(source)] = nil
end)
