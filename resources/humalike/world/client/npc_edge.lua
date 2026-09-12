HumalikeWorldNpcEdge = {
    connected = false,
    ticketPending = false,
    ticketGeneration = 0,
    sequence = 0,
    cursor = 1,
    sentFrames = 0,
    coalescedFrames = 0,
    lastError = nil,
}

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function ambientIdentityMatches(entry, ped, networkId)
    if entry.kind ~= 'ambient' then return true end
    if not NetworkGetEntityIsNetworked(ped)
        or NetworkGetNetworkIdFromEntity(ped) ~= networkId
        or not NetworkDoesEntityExistWithNetworkId(networkId)
        or NetworkGetEntityFromNetworkId(networkId) ~= ped then return false end
    return Entity(ped).state.humalike_npc_id == entry.npcId
end

local function npcSample(candidate)
    local entry, ped = candidate.entry, candidate.entry.entity
    local entityId = tonumber(entry.entityId)
    local networkId = tonumber(entry.networkId) or NetworkGetNetworkIdFromEntity(ped)
    if not entityId or entityId <= 0 or not networkId or networkId <= 0 then return nil end
    if not ambientIdentityMatches(entry, ped, networkId) then return nil end
    local position = candidate.position
    return {
        npc_id = entry.npcId,
        entity_id = entityId,
        network_id = networkId,
        model_hash = entry.modelHash or unsignedHash(GetEntityModel(ped)),
        runtime_token = entry.runtimeToken,
        x = position.x, y = position.y, z = position.z,
        heading = GetEntityHeading(ped),
        zone_code = GetNameOfZone(position.x, position.y, position.z),
        vehicle = HumalikeWorldVehicle.StreamState(ped),
    }
end

local function priority(entry, distanceSquared, speedSquared)
    if entry.activity == 'talking' then return 4 end
    if entry.activity == 'moving' then return 3 end
    local threshold = WorldConfig.collector.movementThreshold
    if speedSquared > threshold * threshold then return 3 end
    if distanceSquared <= 30.0 * 30.0 then return 2 end
    return entry.activity == 'nearby' and 2 or 1
end

local function collect(playerPosition)
    local urgent, regular = {}, {}
    local reportRadiusSquared = WorldConfig.npcEdge.reportRadius
        * WorldConfig.npcEdge.reportRadius
    for _, entry in pairs(HumalikeWorldRegistry.entries) do
        local ped = entry.entity
        if DoesEntityExist(ped) then
            local position = GetEntityCoords(ped)
            local dx, dy, dz = position.x - playerPosition.x, position.y - playerPosition.y,
                position.z - playerPosition.z
            local distanceSquared = dx * dx + dy * dy + dz * dz
            if distanceSquared <= reportRadiusSquared then
                local velocity = GetEntityVelocity(ped)
                local speedSquared = velocity.x * velocity.x + velocity.y * velocity.y
                    + velocity.z * velocity.z
                local candidate = {
                    entry = entry,
                    position = position,
                    priority = priority(entry, distanceSquared, speedSquared),
                }
                local target = candidate.priority >= 3 and urgent or regular
                target[#target + 1] = candidate
            end
        end
    end
    local sorter = function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.entry.npcId < b.entry.npcId
    end
    table.sort(urgent, sorter)
    table.sort(regular, sorter)
    if #urgent == 0 and #regular == 0 then return {} end
    local samples = {}
    for index = 1, math.min(#urgent, WorldConfig.npcEdge.maxNpcsPerFrame) do
        local sample = npcSample(urgent[index])
        if sample then samples[#samples + 1] = sample end
    end
    local remaining = WorldConfig.npcEdge.maxNpcsPerFrame - #samples
    if remaining > 0 and #regular > 0 then
        if HumalikeWorldNpcEdge.cursor > #regular then HumalikeWorldNpcEdge.cursor = 1 end
        for offset = 0, math.min(remaining, #regular) - 1 do
            local index = ((HumalikeWorldNpcEdge.cursor + offset - 1) % #regular) + 1
            local sample = npcSample(regular[index])
            if sample then samples[#samples + 1] = sample end
        end
        HumalikeWorldNpcEdge.cursor = ((HumalikeWorldNpcEdge.cursor + remaining - 1) % #regular) + 1
    end
    return samples
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

RegisterNetEvent('humalike:world:npcEdgeTicket', function(ticket, expectedBootId)
    if expectedBootId ~= HumalikeWorldCollector.bootId or type(ticket) ~= 'table' then return end
    HumalikeWorldNpcEdge.ticketGeneration = HumalikeWorldNpcEdge.ticketGeneration + 1
    HumalikeWorldNpcEdge.ticketPending = false
    ticket.type = 'npc_edge_connect'
    ticket.client_boot_id = HumalikeWorldCollector.bootId
    HumalikeWorldNpcEdge.connected = false
    SendNUIMessage(ticket)
end)

RegisterNetEvent('humalike:world:npcEdgeReconnect', function()
    HumalikeWorldNpcEdge.ticketGeneration = HumalikeWorldNpcEdge.ticketGeneration + 1
    HumalikeWorldNpcEdge.ticketPending = false
    HumalikeWorldNpcEdge.connected = false
    SendNUIMessage({ type = 'npc_edge_disconnect' })
    HumalikeWorldNpcEdge.RequestTicket()
end)

RegisterNUICallback('npcEdgeReady', function(_, callback)
    HumalikeWorldNpcEdge.connected = true
    HumalikeWorldNpcEdge.lastError = nil
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

function HumalikeWorldNpcEdge.BuildPositionsFrame(player, playerPed, sequence)
    return {
        type = 'positions',
        sequence = sequence,
        player = {
            x = player.position.x, y = player.position.y, z = player.position.z,
            effective_voice_distance = player.effectiveVoiceDistance,
            vehicle = HumalikeWorldVehicle.StreamState(playerPed),
        },
        npcs = collect(vector3(player.position.x, player.position.y, player.position.z)),
    }
end

function HumalikeWorldNpcEdge.Start()
    if not WorldConfig.npcEdge.enabled then return end
    CreateThread(function()
        Wait(1000)
        HumalikeWorldNpcEdge.RequestTicket()
        while true do
            Wait(WorldConfig.npcEdge.frameIntervalMs)
            local player = HumalikeWorldCollector.latest
            if HumalikeWorldNpcEdge.connected and player then
                HumalikeWorldNpcEdge.sequence = HumalikeWorldNpcEdge.sequence + 1
                SendNUIMessage({
                    type = 'npc_edge_frame',
                    frame = HumalikeWorldNpcEdge.BuildPositionsFrame(
                        player, PlayerPedId(), HumalikeWorldNpcEdge.sequence
                    ),
                })
                HumalikeWorldNpcEdge.sentFrames = HumalikeWorldNpcEdge.sentFrames + 1
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
