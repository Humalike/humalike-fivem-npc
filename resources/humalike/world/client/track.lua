-- One position cache per registered NPC, sampled by distance; every consumer reads it.
HumalikeWorldTrack = {
    tracks = {},          -- npcId -> track
    count = 0,
    revision = 0,         -- bumped when a track is added or removed
    playerX = 0.0, playerY = 0.0, playerZ = 0.0,
    nearest2 = math.huge, -- squared distance of the closest live track
    lastRegistryRevision = -1,
    changeRevision = 0,   -- bumped whenever any track's reportable state changed
    enteredAt = nil,      -- game time an NPC last came within range
}

local TICK_MS = 100
-- Cadences are counted in passes of TICK_MS, so a late frame does not stretch them.
local NEAR_M, MID_M = 20.0, 60.0
local NEAR_MS, MID_MS, FAR_MS = 150, 400, 1000
local FAST_MOVING_MS = 200
local REPORT_MARGIN_M = 10.0
local SLOW_MS = 1000                -- identity, heading, far vehicle checks
local MOVE_EPSILON = 0.05           -- metres
local MOVING_SPEED = 0.5            -- m/s
local ZONE_REFRESH_M = 30.0
local OWN_VEHICLE_MS = 500
local ENTER_M, LEAVE_M = 10.0, 12.0

local function passes(ms) return (ms + TICK_MS - 1) // TICK_MS end
local NEAR_PASSES, MID_PASSES, FAR_PASSES = passes(NEAR_MS), passes(MID_MS), passes(FAR_MS)
local FAST_MOVING_PASSES, SLOW_PASSES, OWN_VEHICLE_PASSES = passes(FAST_MOVING_MS), passes(SLOW_MS), passes(OWN_VEHICLE_MS)

local tracks = HumalikeWorldTrack.tracks
local vehicleInfo, forgetVehicle, seatOf

local function returnDistance()
    local vehicles = Config and Config.Vehicles
    return vehicles and vehicles.ReturnDistance or 60.0
end

local function reportReach()
    local edge = WorldConfig and WorldConfig.npcEdge
    return (edge and edge.reportRadius or 150.0) + REPORT_MARGIN_M
end

local function bump(track)
    track.version = track.version + 1
    HumalikeWorldTrack.changeRevision = HumalikeWorldTrack.changeRevision + 1
end

vehicleInfo = function(vehicle) return HumalikeWorldVehicle.Info(vehicle) end
forgetVehicle = function(vehicle) HumalikeWorldVehicle.Forget(vehicle) end
seatOf = function(vehicle, ped) return HumalikeWorldVehicle.SeatOf(vehicle, ped) end

local function sampleVehicle(track, pass)
    local ped = track.ped
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        if track.vehicle then
            forgetVehicle(track.vehicle)
            track.vehicle, track.vehicleState, track.seat = nil, nil, nil
            bump(track)
        end
        track.vehiclePass = pass
        return
    end
    local networkId, kind = vehicleInfo(vehicle)
    local seat = track.seat
    if vehicle ~= track.vehicle or seat == nil or pass - track.seatPass >= SLOW_PASSES then
        seat = seatOf(vehicle, ped)
        track.seatPass = pass
    end
    local state = track.vehicleState
    if not networkId or not seat then
        if state then bump(track) end
        track.vehicle, track.vehicleState, track.seat = vehicle, nil, seat
    elseif not state or state.network_id ~= networkId or state.seat ~= seat or state.kind ~= kind then
        track.vehicle, track.seat = vehicle, seat
        track.vehicleState = { network_id = networkId, seat = seat, kind = kind }
        bump(track)
    else
        track.vehicle, track.seat = vehicle, seat
    end
    track.vehiclePass = pass
end

local function ownNetOf(value)
    if type(value) ~= 'number' or value <= 0 then return false end
    return value
end

-- Read at the first sample; a bag that arrives later is handed over by its change handler.
local function sampleOwnVehicle(track, pass)
    track.ownPass = pass
    local networkId = track.ownNet
    if networkId == nil then
        networkId = ownNetOf(Entity(track.ped).state.humalike_vehicle_net)
        track.ownNet = networkId
    end
    local own = nil
    if networkId and NetworkDoesEntityExistWithNetworkId(networkId) then
        local vehicle = NetworkGetEntityFromNetworkId(networkId)
        if vehicle and vehicle > 0 and DoesEntityExist(vehicle) then
            local at = GetEntityCoords(vehicle)
            local dx, dy, dz = at.x - track.x, at.y - track.y, at.z - track.z
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            if track.ownHandle ~= vehicle then
                track.ownHandle = vehicle
                track.ownKind = IsThisModelABike(GetEntityModel(vehicle)) and 'bike' or 'car'
            end
            own = {
                network_id = networkId,
                distance_m = distance,
                in_reach = distance <= returnDistance(),
                kind = track.ownKind,
            }
        end
    end
    local previous = track.ownVehicle
    if (own == nil) ~= (previous == nil)
        or (own and (own.network_id ~= previous.network_id or own.in_reach ~= previous.in_reach
            or math.abs(own.distance_m - previous.distance_m) > 0.5)) then
        bump(track)
    end
    track.ownVehicle = own
end

local function identityMatches(track)
    local entry, ped = track.entry, track.ped
    if NetworkGetNetworkIdFromEntity(ped) ~= track.networkId then return false end
    if entry.kind ~= 'ambient' then return true end
    return AmbientPeds ~= nil and AmbientPeds[track.npcId] == ped
end

local function sample(track, now, pass, px, py, pz)
    local ped = track.ped
    -- A ped that is gone reads as the origin: its existence is asked only then.
    local at = GetEntityCoords(ped)
    local x, y, z = at.x, at.y, at.z
    if x == 0.0 and y == 0.0 and z == 0.0 and not DoesEntityExist(ped) then
        if track.exists then
            track.exists = false
            track.dist2 = math.huge
            bump(track)
        end
        track.sampledAt, track.nextPass = now, pass + SLOW_PASSES
        return
    end
    local dx, dy, dz = x - track.x, y - track.y, z - track.z
    local moved2 = dx * dx + dy * dy + dz * dz
    local elapsed = (now - track.sampledAt) / 1000.0
    -- Speed between two samples, not against the recorded position.
    if track.exists and elapsed > 0 then
        local sx, sy, sz = x - track.sampleX, y - track.sampleY, z - track.sampleZ
        track.speed = math.sqrt(sx * sx + sy * sy + sz * sz) / elapsed
    else
        track.speed = 0.0
    end
    track.sampleX, track.sampleY, track.sampleZ = x, y, z
    if track.networkId == nil then
        local networkId = tonumber(NetworkGetNetworkIdFromEntity(ped))
        if networkId and networkId > 0 then track.networkId = networkId end
    end
    if not track.exists or moved2 > MOVE_EPSILON * MOVE_EPSILON then
        track.x, track.y, track.z = x, y, z
        track.exists = true
        bump(track)
    end
    local ex, ey, ez = x - px, y - py, z - pz
    track.dist2 = ex * ex + ey * ey + ez * ez
    track.sampledAt = now

    local near = track.dist2 <= NEAR_M * NEAR_M
    if track.identityPass == nil or pass - track.identityPass >= SLOW_PASSES then
        track.identityPass = pass
        local ok = identityMatches(track)
        if ok ~= track.identityOk then
            track.identityOk = ok
            bump(track)
        end
        if track.dist2 <= MID_M * MID_M then track.heading = GetEntityHeading(ped) end
    end
    local zx, zy = x - track.zoneX, y - track.zoneY
    if track.zone == nil or zx * zx + zy * zy > ZONE_REFRESH_M * ZONE_REFRESH_M then
        track.zone = GetNameOfZone(x, y, z) or false
        track.zoneX, track.zoneY = x, y
    end
    if near or track.vehicle or track.ownNet or pass - track.vehiclePass >= SLOW_PASSES then
        sampleVehicle(track, pass)
    end
    if track.ownNet ~= false and (track.ownNet == nil or pass - track.ownPass >= OWN_VEHICLE_PASSES) then
        sampleOwnVehicle(track, pass)
    end

    local interval
    if near then
        interval = NEAR_PASSES
    elseif track.dist2 <= MID_M * MID_M then
        interval = MID_PASSES
    else
        interval = FAR_PASSES
    end
    if track.speed > MOVING_SPEED and interval > FAST_MOVING_PASSES then
        local reach = reportReach()
        if track.dist2 <= reach * reach then interval = FAST_MOVING_PASSES end
    end
    local wait = interval
    if interval >= MID_PASSES then
        -- The slow cadences are spread over the passes.
        wait = (track.slot - pass) % interval
        if wait == 0 then wait = interval end
    end
    track.nextPass = pass + wait
end

local function newTrack(npcId, entry)
    return {
        npcId = npcId,
        entry = entry,
        ped = entry.entity,
        generation = entry.generation,
        version = 0,
        networkId = tonumber(entry.networkId),
        slot = (tonumber(entry.networkId) or 0) % FAR_PASSES,
        exists = false,
        x = 0.0, y = 0.0, z = 0.0, dist2 = math.huge, speed = 0.0,
        sampleX = 0.0, sampleY = 0.0, sampleZ = 0.0,
        sampledAt = 0, nextPass = -math.huge,
        identityOk = true, identityPass = nil,
        inRange = false,
        heading = 0.0,
        zone = nil, zoneX = 0.0, zoneY = 0.0,
        vehicle = nil, vehicleState = nil, seat = nil, seatPass = -math.huge, vehiclePass = -math.huge,
        ownNet = nil, ownVehicle = nil, ownPass = -math.huge, ownHandle = nil, ownKind = nil,
    }
end

local function syncRegistry()
    local registry = HumalikeWorldRegistry
    if registry.revision == HumalikeWorldTrack.lastRegistryRevision then return end
    HumalikeWorldTrack.lastRegistryRevision = registry.revision
    local changed = false
    for npcId, entry in pairs(registry.entries) do
        local track = tracks[npcId]
        if not track or track.entry ~= entry then
            local fresh = newTrack(npcId, entry)
            if track then
                -- Versions go on across a replaced track, so readers see it as changed.
                fresh.version = track.version + 1
            end
            if track and track.ped == entry.entity then
                fresh.exists, fresh.x, fresh.y, fresh.z = track.exists, track.x, track.y, track.z
                fresh.sampleX, fresh.sampleY, fresh.sampleZ = track.sampleX, track.sampleY, track.sampleZ
                fresh.dist2, fresh.sampledAt = track.dist2, track.sampledAt
                fresh.inRange = track.inRange
                fresh.zone, fresh.zoneX, fresh.zoneY = track.zone, track.zoneX, track.zoneY
                fresh.ownNet = track.ownNet
                if fresh.networkId == nil then fresh.networkId = track.networkId end
            end
            if not track then HumalikeWorldTrack.count = HumalikeWorldTrack.count + 1 end
            tracks[npcId] = fresh
            changed = true
        end
    end
    for npcId, track in pairs(tracks) do
        if registry.entries[npcId] ~= track.entry then
            if track.vehicle then forgetVehicle(track.vehicle) end
            tracks[npcId] = nil
            HumalikeWorldTrack.count = HumalikeWorldTrack.count - 1
            changed = true
        end
    end
    if changed then
        HumalikeWorldTrack.revision = HumalikeWorldTrack.revision + 1
        HumalikeWorldTrack.changeRevision = HumalikeWorldTrack.changeRevision + 1
    end
end

function HumalikeWorldTrack.Sample(now, px, py, pz, pass)
    pass = pass or now // TICK_MS
    syncRegistry()
    HumalikeWorldTrack.playerX, HumalikeWorldTrack.playerY, HumalikeWorldTrack.playerZ = px, py, pz
    local nearest2, sampled = math.huge, 0
    for _, track in pairs(tracks) do
        if pass >= track.nextPass then
            sample(track, now, pass, px, py, pz)
            sampled = sampled + 1
        elseif track.exists then
            local ex, ey, ez = track.x - px, track.y - py, track.z - pz
            track.dist2 = ex * ex + ey * ey + ez * ez
        end
        local dist2 = track.dist2
        if dist2 < nearest2 then nearest2 = dist2 end
        if track.inRange then
            if dist2 > LEAVE_M * LEAVE_M then track.inRange = false end
        elseif dist2 <= ENTER_M * ENTER_M then
            track.inRange = true
            HumalikeWorldTrack.enteredAt = now
        end
    end
    HumalikeWorldTrack.nearest2 = nearest2
    return sampled
end

function HumalikeWorldTrack.Get(npcId)
    return tracks[npcId]
end

-- The handler runs before the bag holds the value: the value it is handed is kept.
AddStateBagChangeHandler('humalike_vehicle_net', nil, function(bagName, _, value)
    local ped = GetEntityFromStateBagName(bagName)
    if not ped or ped <= 0 then return end
    local networkId = ownNetOf(value)
    for _, track in pairs(tracks) do
        if track.ped == ped and track.ownNet ~= networkId then
            track.ownNet = networkId
            track.ownPass = -math.huge
            if not networkId and track.ownVehicle then
                track.ownVehicle = nil
                bump(track)
            end
        end
    end
end)

function HumalikeWorldTrack.AnyWithin(radius)
    return HumalikeWorldTrack.nearest2 <= radius * radius
end

function HumalikeWorldTrack.Start()
    HumalikePulse.Every('tracker', TICK_MS, function(now)
        local ped = HumalikePulse.Ped()
        if ped and ped > 0 then
            local at = HumalikePulse.Coords(ped)
            HumalikeWorldTrack.Sample(now, at.x, at.y, at.z, HumalikePulse.Beat(TICK_MS))
        end
    end, 30)
end
