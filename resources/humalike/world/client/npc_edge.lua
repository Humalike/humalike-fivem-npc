HumalikeWorldNpcEdge = {
    connected = false,
    ticketPending = false,
    ticketGeneration = 0,
    sequence = 0,
    cursor = 1,
    sentFrames = 0,
    coalescedFrames = 0,
    lastError = nil,
    lastSentAt = 0,
    lastKeyframeAt = nil, -- nil: the next frame is a keyframe
}

-- The edge keeps an NPC's last position until it is told otherwise, so a frame
-- carries only what changed. The whole scene goes out again every KEYFRAME_MS
-- (a frame can be lost when two land in one of the edge's 200 ms windows),
-- and a frame goes out at least every KEEPALIVE_MS: the edge forgets a player
-- it has not heard from for three seconds.
local KEEPALIVE_MS = 1000
local KEYFRAME_MS = 2000
local PLAYER_MOVE_EPSILON = 0.1 -- metres

local sent = {} -- npcId -> track version last reported
local selectedRevision = nil -- HumalikeWorldTrack.changeRevision the last selection saw

-- Frames are encoded by hand: the generic JSON encoder spent a millisecond or
-- two on a 32-NPC frame, five times a second.
local function jsonString(value)
    value = tostring(value)
    if value:find('[%c"\\]') then
        value = value:gsub('[%c"\\]', function(char)
            if char == '"' then return '\\"' end
            if char == '\\' then return '\\\\' end
            return ('\\u%04x'):format(char:byte())
        end)
    end
    return '"' .. value .. '"'
end

local function finite(value)
    value = tonumber(value) or 0.0
    if value ~= value or value == math.huge or value == -math.huge then return 0.0 end
    return value
end

local function vehicleJson(state)
    if not state then return '' end
    return (',"vehicle":{"network_id":%d,"seat":%d,"kind":"%s"}'):format(
        state.network_id, state.seat, state.kind == 'bike' and 'bike' or 'car')
end

local function ownVehicleJson(own)
    if not own then return '' end
    return (',"own_vehicle":{"network_id":%d,"distance_m":%.2f,"in_reach":%s,"kind":"%s"}'):format(
        own.network_id, finite(own.distance_m), own.in_reach and 'true' or 'false',
        own.kind == 'bike' and 'bike' or 'car')
end

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

-- The identity half of an NPC's sample never changes for a registration.
local function prefixOf(track)
    if track.edgePrefix and track.edgePrefixGeneration == track.generation then
        return track.edgePrefix
    end
    local entry = track.entry
    local modelHash = entry.modelHash
    if not modelHash then modelHash = unsignedHash(GetEntityModel(track.ped)) end
    track.edgePrefix = ('{"npc_id":%s,"entity_id":%d,"network_id":%d,"model_hash":%d,"runtime_token":%s'):format(
        jsonString(entry.npcId), entry.entityId, entry.networkId, modelHash, jsonString(entry.runtimeToken))
    track.edgePrefixGeneration = track.generation
    return track.edgePrefix
end

local function npcJson(track)
    local zone = track.zone and (',"zone_code":%s'):format(jsonString(track.zone)) or ''
    return ('%s,"x":%.3f,"y":%.3f,"z":%.3f,"heading":%.2f%s%s%s}'):format(
        prefixOf(track), finite(track.x), finite(track.y), finite(track.z), finite(track.heading),
        zone, vehicleJson(track.vehicleState), ownVehicleJson(track.ownVehicle))
end

local function reportable(track)
    local entry = track.entry
    local entityId, networkId = tonumber(entry.entityId), tonumber(entry.networkId)
    return track.exists and track.identityOk and entityId and entityId > 0 and networkId and networkId > 0
end

local function priority(track)
    local activity = track.entry.activity
    if activity == 'talking' then return 4 end
    if activity == 'moving' then return 3 end
    if track.speed > WorldConfig.collector.movementThreshold then return 3 end
    if track.dist2 <= 30.0 * 30.0 then return 2 end
    return activity == 'nearby' and 2 or 1
end

local sorter = function(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    return a.npcId < b.npcId
end

-- The tracks to report this frame, urgent ones first. A keyframe takes every
-- reportable track; a delta takes the ones whose cache changed since they were
-- last reported. More than the per-frame cap rotates through the rest.
function HumalikeWorldNpcEdge.Select(keyframe)
    local urgent, regular = {}, {}
    local radius2 = WorldConfig.npcEdge.reportRadius * WorldConfig.npcEdge.reportRadius
    for npcId, track in pairs(HumalikeWorldTrack.tracks) do
        if reportable(track) and track.dist2 <= radius2
            and (keyframe or sent[npcId] ~= track.version) then
            track.priority = priority(track)
            local target = track.priority >= 3 and urgent or regular
            target[#target + 1] = track
        end
    end
    for npcId in pairs(sent) do
        if not HumalikeWorldTrack.tracks[npcId] then sent[npcId] = nil end
    end
    if #urgent == 0 and #regular == 0 then return urgent end
    table.sort(urgent, sorter)
    table.sort(regular, sorter)
    local cap = WorldConfig.npcEdge.maxNpcsPerFrame
    local selected = {}
    for index = 1, math.min(#urgent, cap) do selected[#selected + 1] = urgent[index] end
    local remaining = cap - #selected
    if remaining > 0 and #regular > 0 then
        if HumalikeWorldNpcEdge.cursor > #regular then HumalikeWorldNpcEdge.cursor = 1 end
        for offset = 0, math.min(remaining, #regular) - 1 do
            local index = ((HumalikeWorldNpcEdge.cursor + offset - 1) % #regular) + 1
            selected[#selected + 1] = regular[index]
        end
        HumalikeWorldNpcEdge.cursor = ((HumalikeWorldNpcEdge.cursor + remaining - 1) % #regular) + 1
    end
    return selected
end

-- The NUI message, pre-encoded: `{"type":"npc_edge_frame","frame":{...}}`.
function HumalikeWorldNpcEdge.Encode(player, sequence, selected)
    local parts = {}
    for index, track in ipairs(selected) do
        parts[index] = npcJson(track)
        sent[track.npcId] = track.version
    end
    local position = player.position
    local vehicle = player.vehicle
    local vehiclePart = ''
    if vehicle and vehicle.networkId and vehicle.seat then
        vehiclePart = (',"vehicle":{"network_id":%d,"seat":%d,"kind":"%s"}'):format(
            vehicle.networkId, vehicle.seat, vehicle.kind == 'bike' and 'bike' or 'car')
    end
    return ('{"type":"npc_edge_frame","frame":{"type":"positions","sequence":%d,"player":{"x":%.3f,"y":%.3f,"z":%.3f,"effective_voice_distance":%.2f%s},"npcs":[%s]}}'):format(
        sequence, finite(position.x), finite(position.y), finite(position.z),
        finite(player.effectiveVoiceDistance), vehiclePart, table.concat(parts, ','))
end

function HumalikeWorldNpcEdge.RequestTicket()
    if not WorldConfig.npcEdge.enabled or HumalikeWorldNpcEdge.connected
        or HumalikeWorldNpcEdge.ticketPending then return end
    HumalikeWorldNpcEdge.ticketPending = true
    HumalikeWorldNpcEdge.ticketGeneration = HumalikeWorldNpcEdge.ticketGeneration + 1
    local generation = HumalikeWorldNpcEdge.ticketGeneration
    TriggerServerEvent('humalike:world:requestNpcEdgeTicket', HumalikeWorldCollector.bootId)
    SetTimeout(5000, function()
        if generation == HumalikeWorldNpcEdge.ticketGeneration then
            HumalikeWorldNpcEdge.ticketPending = false
        end
    end)
end

local function resetReports()
    sent = {}
    selectedRevision = nil
    HumalikeWorldNpcEdge.lastKeyframeAt = nil
end

RegisterNetEvent('humalike:world:npcEdgeTicket', function(ticket, expectedBootId)
    if expectedBootId ~= HumalikeWorldCollector.bootId or type(ticket) ~= 'table' then return end
    HumalikeWorldNpcEdge.ticketGeneration = HumalikeWorldNpcEdge.ticketGeneration + 1
    HumalikeWorldNpcEdge.ticketPending = false
    ticket.type = 'npc_edge_connect'
    ticket.client_boot_id = HumalikeWorldCollector.bootId
    HumalikeWorldNpcEdge.connected = false
    resetReports()
    SendNUIMessage(ticket)
end)

RegisterNetEvent('humalike:world:npcEdgeReconnect', function()
    HumalikeWorldNpcEdge.ticketGeneration = HumalikeWorldNpcEdge.ticketGeneration + 1
    HumalikeWorldNpcEdge.ticketPending = false
    HumalikeWorldNpcEdge.connected = false
    resetReports()
    SendNUIMessage({ type = 'npc_edge_disconnect' })
    HumalikeWorldNpcEdge.RequestTicket()
end)

RegisterNUICallback('npcEdgeReady', function(_, callback)
    HumalikeWorldNpcEdge.connected = true
    HumalikeWorldNpcEdge.lastError = nil
    resetReports() -- a fresh socket starts with a keyframe
    TriggerEvent('humalike:world:npcSinkStatus', 'ready')
    callback({ ok = true })
end)

RegisterNUICallback('npcEdgeClosed', function(body, callback)
    HumalikeWorldNpcEdge.connected = false
    HumalikeWorldNpcEdge.lastError = type(body) == 'table' and body.reason or nil
    TriggerEvent('humalike:world:npcSinkStatus', 'closed')
    callback({ ok = true })
end)

RegisterNUICallback('npcEdgeStats', function(body, callback)
    if type(body) == 'table' then
        HumalikeWorldNpcEdge.coalescedFrames = tonumber(body.coalescedFrames)
            or HumalikeWorldNpcEdge.coalescedFrames
    end
    callback({ ok = true })
end)

local lastPlayer = nil -- position and seat of the last frame sent

local function playerChanged(player)
    local last = lastPlayer
    if not last then return true end
    local p = player.position
    if math.abs(p.x - last.x) > PLAYER_MOVE_EPSILON or math.abs(p.y - last.y) > PLAYER_MOVE_EPSILON
        or math.abs(p.z - last.z) > PLAYER_MOVE_EPSILON then return true end
    local vehicle = player.vehicle
    local networkId, seat = vehicle and vehicle.networkId or false, vehicle and vehicle.seat or false
    return networkId ~= last.networkId or seat ~= last.seat
        or player.effectiveVoiceDistance ~= last.voiceDistance
end

-- One frame decision; returns the encoded message or nil when nothing is due.
local EMPTY = {}

function HumalikeWorldNpcEdge.Frame(player, now)
    local lastKeyframeAt = HumalikeWorldNpcEdge.lastKeyframeAt
    local keyframe = lastKeyframeAt == nil or now - lastKeyframeAt >= KEYFRAME_MS
    local revision = HumalikeWorldTrack.changeRevision
    -- With no track changed since the last pass, a delta would be empty: the
    -- selection (a walk over every track) is skipped.
    local selected = EMPTY
    if keyframe or revision ~= selectedRevision then
        selected = HumalikeWorldNpcEdge.Select(keyframe)
        selectedRevision = revision
    end
    if #selected == 0 and not keyframe and not playerChanged(player)
        and now - HumalikeWorldNpcEdge.lastSentAt < KEEPALIVE_MS then
        return nil
    end
    HumalikeWorldNpcEdge.sequence = HumalikeWorldNpcEdge.sequence + 1
    local message = HumalikeWorldNpcEdge.Encode(player, HumalikeWorldNpcEdge.sequence, selected)
    HumalikeWorldNpcEdge.lastSentAt = now
    if keyframe then HumalikeWorldNpcEdge.lastKeyframeAt = now end
    local vehicle = player.vehicle
    lastPlayer = {
        x = player.position.x, y = player.position.y, z = player.position.z,
        networkId = vehicle and vehicle.networkId or false, seat = vehicle and vehicle.seat or false,
        voiceDistance = player.effectiveVoiceDistance,
    }
    return message
end

function HumalikeWorldNpcEdge.Start()
    if not WorldConfig.npcEdge.enabled then return end
    CreateThread(function()
        Wait(1000)
        HumalikeWorldNpcEdge.RequestTicket()
        local startedAt = GetGameTimer()
        while true do
            Wait(math.max(0, WorldConfig.npcEdge.frameIntervalMs - (GetGameTimer() - startedAt)))
            startedAt = GetGameTimer()
            local player = HumalikeWorldCollector.latest
            if HumalikeWorldNpcEdge.connected and player then
                local message = HumalikeWorldNpcEdge.Frame(player, startedAt)
                if message and HumalikeWorldNpcEdge.connected then
                    SendNuiMessage(message)
                    HumalikeWorldNpcEdge.sentFrames = HumalikeWorldNpcEdge.sentFrames + 1
                end
            end
        end
    end)
    CreateThread(function()
        while true do
            Wait(WorldConfig.npcEdge.ticketRetryMs)
            if not HumalikeWorldNpcEdge.connected then HumalikeWorldNpcEdge.RequestTicket() end
        end
    end)
    CreateThread(function()
        local delayMs = WorldConfig.npcEdge.ticketRefreshMs or 12000
        local wasConnected = false
        local refreshAt = nil
        while true do
            Wait(1000)
            local c = HumalikeWorldNpcEdge.connected
            if c and not wasConnected then
                refreshAt = GetGameTimer() + delayMs
            elseif not c then
                refreshAt = nil
            end
            if c and refreshAt and GetGameTimer() >= refreshAt then
                refreshAt = nil
                HumalikeWorldNpcEdge.connected = false
                HumalikeWorldNpcEdge.RequestTicket()
            end
            wasConnected = c
        end
    end)
end
