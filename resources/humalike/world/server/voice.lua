local voiceSessions = {}
HumalikeWorldVoice = {}

function HumalikeWorldVoice.SessionId(playerId)
    local session = voiceSessions[tonumber(playerId)]
    return session and session.sessionId or nil
end
local pendingAuthority = {}
local voiceRevision = 0
local authorityRequestInFlight = false
local voiceRequestSequence = 0
local pendingVoiceRequests = {}
local assignmentRefreshPlayers = {}
local requestVoiceSession

local function runtimeServerId()
    local credentials = HumaLike.RuntimeCredentials()
    return credentials and credentials.serverId or nil
end

local function request(method, path, body, callback)
    if not WorldConfig.voice.enabled then callback(0, nil) return end
    if method ~= 'POST' then callback(405, nil) return end
    HumaLike.PostVoice(path, body, callback)
end

local function voiceState(state)
    return {
        dimension = state.routingBucket,
        loaded = state.loaded,
        dead = state.dead,
        deafened = state.deafened,
    }
end

local function queue(playerId, removed)
    local session = voiceSessions[playerId]
    if not session then return end
    local state = HumalikeWorldAuthority.players[playerId]
    pendingAuthority[playerId] = {
        playerId = tostring(playerId),
        sessionId = session.sessionId,
        removed = removed or nil,
        state = removed and nil or state and voiceState(state) or nil,
    }
end

local function publish(mode, players, callback)
    local serverId = runtimeServerId()
    if not serverId then callback(false) return end
    voiceRevision = voiceRevision + 1
    request('POST', '/v1/fivem/state', {
        serverId = serverId,
        epoch = HumalikeWorldAuthority.epoch,
        mode = mode,
        revision = voiceRevision,
        players = players,
    }, function(status)
        callback(status >= 200 and status < 300)
    end)
end

local function fullSnapshot()
    if authorityRequestInFlight then return end
    local players = {}
    for playerId, session in pairs(voiceSessions) do
        local state = HumalikeWorldAuthority.players[playerId]
        if state then
            players[#players + 1] = {
                playerId = tostring(playerId),
                sessionId = session.sessionId,
                state = voiceState(state),
            }
        end
    end
    authorityRequestInFlight = true
    publish('snapshot', players, function() authorityRequestInFlight = false end)
end

AddEventHandler('humalike:core:ready', function()
    authorityRequestInFlight = false
    for playerId in pairs(pendingVoiceRequests) do
        pendingVoiceRequests[playerId] = nil
        assignmentRefreshPlayers[playerId] = true
    end
    fullSnapshot()
    for playerId in pairs(assignmentRefreshPlayers) do
        assignmentRefreshPlayers[playerId] = nil
        print(('[humalike] voice_session_retry reason=runtime_refreshed player_id=%d')
            :format(playerId))
        requestVoiceSession(playerId)
    end
end)

requestVoiceSession = function(rawPlayerId)
    local playerId = tonumber(rawPlayerId)
    if playerId and assignmentRefreshPlayers[playerId] then return end
    local state = playerId and HumalikeWorldAuthority.players[playerId]
    local serverId = runtimeServerId()
    if not state or not serverId then
        TriggerClientEvent('humalike:world:voiceSessionFailed', rawPlayerId, 409)
        return
    end
    voiceRequestSequence = voiceRequestSequence + 1
    local requestSequence = voiceRequestSequence
    local expectedGeneration = state.generation
    pendingVoiceRequests[playerId] = requestSequence
    request('POST', '/v1/fivem/sessions', {
        serverId = serverId,
        epoch = HumalikeWorldAuthority.epoch,
        playerId = tostring(playerId),
        state = voiceState(state),
    }, function(status, response)
        local current = HumalikeWorldAuthority.players[playerId]
        if pendingVoiceRequests[playerId] ~= requestSequence then return end
        if not current then
            pendingVoiceRequests[playerId] = nil
            return
        end
        if current.generation ~= expectedGeneration then
            pendingVoiceRequests[playerId] = nil
            TriggerClientEvent('humalike:world:voiceSessionFailed', playerId, 409)
            return
        end
        if status == 409 and HumaLike.ErrorCode(response) == 'assignment_stale' then
            pendingVoiceRequests[playerId] = nil
            assignmentRefreshPlayers[playerId] = true
            print(('[humalike] voice_assignment_stale server_id=%s player_id=%d action=refresh_runtime')
                :format(serverId, playerId))
            HumaLike.RequestBootstrap('voice assignment stale', 1, true)
            return
        end
        pendingVoiceRequests[playerId] = nil
        if status < 200 or status >= 300 or not response then
            TriggerClientEvent('humalike:world:voiceSessionFailed', playerId, status)
            return
        end
        if not response.sessionId or not response.ticket then
            TriggerClientEvent('humalike:world:voiceSessionFailed', playerId, 0)
            return
        end
        voiceSessions[playerId] = { sessionId = response.sessionId }
        queue(playerId, false)
        if HumalikeWorldCabins then HumalikeWorldCabins.Publish(false, false) end
        TriggerClientEvent('humalike:world:voiceSessionReady', playerId, {
            ticket = response.ticket,
            controlUrl = response.controlUrl,
            expiresAt = response.expiresAt,
        })
    end)
end

RegisterNetEvent('humalike:world:requestVoiceSession', function()
    requestVoiceSession(source)
end)

AddEventHandler('humalike:world:authorityChanged', function(delta)
    local playerId = tonumber(delta.playerId)
    if delta.kind == 'remove' then
        pendingVoiceRequests[playerId] = nil
        assignmentRefreshPlayers[playerId] = nil
        queue(playerId, true)
        voiceSessions[playerId] = nil
    else
        queue(playerId, false)
    end
end)

CreateThread(function()
    while true do
        Wait(WorldConfig.voice.deltaBatchIntervalMs)
        if WorldConfig.voice.enabled and not authorityRequestInFlight and next(pendingAuthority) then
            local batch, players = pendingAuthority, {}
            pendingAuthority = {}
            for _, player in pairs(batch) do players[#players + 1] = player end
            authorityRequestInFlight = true
            publish('delta', players, function(ok)
                authorityRequestInFlight = false
                if not ok then
                    for playerId, player in pairs(batch) do
                        if pendingAuthority[playerId] == nil then pendingAuthority[playerId] = player end
                    end
                end
            end)
        end
    end
end)

CreateThread(function()
    Wait(5000)
    while true do
        if WorldConfig.voice.enabled then fullSnapshot() end
        Wait(WorldConfig.voice.snapshotIntervalMs)
    end
end)
