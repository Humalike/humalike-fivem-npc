local observations = {}
local pendingBySource = {}
local observedEventAt = {}
local damagedEventAt = {}
local lastPruneAt

local function validNetworkId(value)
    return type(value) == 'number' and value == math.floor(value)
        and value >= 1 and value <= 4294967295
end

local function finite(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function observationKey(bucket, vehicle, networkId)
    return ('%d:%d:%d'):format(bucket, vehicle, networkId)
end

local function pruneObservations(now)
    local retention = Config.VehicleDamage.ObservationRetentionMs
    if lastPruneAt and now >= lastPruneAt and now - lastPruneAt < retention then return end
    lastPruneAt = now
    for key, observation in pairs(observations) do
        if now < observation.lastSeenAt
            or now - observation.lastSeenAt >= retention then observations[key] = nil end
    end
end

local function observeOccupiedVehicle(playerId, now)
    local ped = GetPlayerPed(playerId)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle <= 0 or not DoesEntityExist(vehicle)
        or GetEntityType(vehicle) ~= 2 then return nil end

    local networkId = NetworkGetNetworkIdFromEntity(vehicle)
    local body = GetVehicleBodyHealth(vehicle)
    local engine = GetVehicleEngineHealth(vehicle)
    if not validNetworkId(networkId) or not finite(body) or not finite(engine) then return nil end

    local bucket = GetPlayerRoutingBucket(playerId)
    local key = observationKey(bucket, vehicle, networkId)
    local observation = observations[key]
    local created = observation == nil
    if created then
        observation = { body = body, engine = engine }
        observations[key] = observation
    else
        observation.body = math.max(observation.body, body)
        observation.engine = math.max(observation.engine, engine)
    end
    observation.lastSeenAt = now
    return observation, key, networkId, body, engine, created
end

local function post(observation, delay, attempt)
    attempt = attempt or 1
    HumalikeHttp.PostAction('ingest_world_event', observation, function(ok, status, body)
        if ok and body and body.ok == true then return end
        if attempt < 5 and (status == 0 or status >= 500) then
            SetTimeout(delay, function() post(observation, delay * 2, attempt + 1) end)
        end
    end)
end

local function emitIfReady(playerId, observation, networkId, body, engine, now)
    local damage = math.max(observation.body - body, observation.engine - engine)
    if damage < Config.VehicleDamage.SignificantHealthDrop then return false end
    local last = observation.lastReportAt
    if last and now >= last
        and now - last < Config.VehicleDamage.ServerCooldownMs then return false end

    local severe = damage >= Config.VehicleDamage.SevereHealthDrop
        or engine <= Config.VehicleDamage.SevereEngineHealth
    observation.body = body
    observation.engine = engine
    observation.lastReportAt = now
    post({
        fivem_session_id = playerId,
        source_event_id = HumalikeHttp.NextSourceEventId(playerId),
        occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        event = {
            type = 'vehicle_damaged',
            vehicle_network_id = networkId,
            severity = severe and 'severe' or 'significant',
        },
    }, 1000)
    return true
end

local function pendingExpired(pending, now)
    return now < pending.createdAt
        or now - pending.createdAt >= Config.VehicleDamage.PendingCandidateMs
end

local function retainPending(playerId, key, networkId, now)
    local pending = pendingBySource[playerId]
    if pending and pending.key == key then return end
    pendingBySource[playerId] = {
        key = key,
        networkId = networkId,
        createdAt = now,
    }
end

local function reconcilePending(playerId, observation, key, networkId, body, engine, now)
    local pending = pendingBySource[playerId]
    if not pending then return end
    if not observation or pending.key ~= key or pending.networkId ~= networkId
        or pendingExpired(pending, now) then
        pendingBySource[playerId] = nil
        return
    end
    if emitIfReady(playerId, observation, networkId, body, engine, now) then
        pendingBySource[playerId] = nil
    end
end

local function throttled(states, playerId, now)
    local last = states[playerId]
    if last and now >= last
        and now - last < Config.VehicleDamage.UntrustedEventThrottleMs then return true end
    states[playerId] = now
    return false
end

CreateThread(function()
    while true do
        Wait(Config.VehicleDamage.ServerPollIntervalMs)
        local now = GetGameTimer()
        pruneObservations(now)
        for _, rawPlayerId in ipairs(GetPlayers()) do
            local playerId = tonumber(rawPlayerId)
            if playerId and HumalikePlayer.IsCharacterLoaded(playerId) then
                local observation, key, networkId, body, engine =
                    observeOccupiedVehicle(playerId, now)
                reconcilePending(playerId, observation, key, networkId, body, engine, now)
            elseif playerId then
                pendingBySource[playerId] = nil
            end
        end
    end
end)

local function validReporter(playerId, vehicleNetworkId)
    return playerId and playerId > 0 and playerId % 1 == 0
        and validNetworkId(vehicleNetworkId)
        and HumalikePlayer.IsCharacterLoaded(playerId)
end

RegisterNetEvent('humalike:npc:vehicleObserved')
AddEventHandler('humalike:npc:vehicleObserved', function(vehicleNetworkId)
    local playerId = tonumber(source)
    if not validReporter(playerId, vehicleNetworkId) then return end
    local now = GetGameTimer()
    if throttled(observedEventAt, playerId, now) then return end
    pruneObservations(now)
    local observation, key, actualNetworkId = observeOccupiedVehicle(playerId, now)
    if not observation or actualNetworkId ~= vehicleNetworkId then return end
    local pending = pendingBySource[playerId]
    if pending and pending.key ~= key then pendingBySource[playerId] = nil end
end)

RegisterNetEvent('humalike:npc:vehicleDamaged')
AddEventHandler('humalike:npc:vehicleDamaged', function(vehicleNetworkId)
    local playerId = tonumber(source)
    if not validReporter(playerId, vehicleNetworkId) then return end
    local now = GetGameTimer()
    if throttled(damagedEventAt, playerId, now) then return end
    pruneObservations(now)
    local observation, key, actualNetworkId, body, engine =
        observeOccupiedVehicle(playerId, now)
    if not observation or actualNetworkId ~= vehicleNetworkId then return end
    local pending = pendingBySource[playerId]
    if pending and pending.key ~= key then pendingBySource[playerId] = nil end
    if emitIfReady(playerId, observation, actualNetworkId, body, engine, now) then
        pendingBySource[playerId] = nil
    else
        retainPending(playerId, key, actualNetworkId, now)
    end
end)

AddEventHandler('playerDropped', function()
    local playerId = tonumber(source)
    if not playerId then return end
    pendingBySource[playerId] = nil
    observedEventAt[playerId] = nil
    damagedEventAt[playerId] = nil
end)
