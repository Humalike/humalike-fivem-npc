-- One spatial cache for every registered NPC. The edge frame, the labels, the
-- direct voice targets and the shove detector used to walk the registry on
-- their own clocks, each paying its own natives per NPC; they read this
-- cache instead. A track is sampled on a cadence set by its distance to the
-- player (and faster while it moves), so a crowd across the street costs a
-- native a second, not a dozen a frame.
HumalikeWorldTrack = {
    tracks = {},          -- npcId -> track
    count = 0,
    revision = 0,         -- bumped when a track is added or removed
    playerX = 0.0, playerY = 0.0, playerZ = 0.0,
    nearest2 = math.huge, -- squared distance of the closest live track
    lastRegistryRevision = -1,
    changeRevision = 0,   -- bumped whenever any track's reportable state changed
}

local TICK_MS = 100
-- Sample cadences by distance; a moving track never waits longer than FAST_MOVING_MS.
local NEAR_M, MID_M = 20.0, 60.0
local NEAR_MS, MID_MS, FAR_MS = 150, 400, 1000
local FAST_MOVING_MS = 200
local SLOW_MS = 1000                -- identity, heading, far vehicle checks
local MOVE_EPSILON = 0.05           -- metres; below this a position is the same
local MOVING_SPEED = 0.5            -- m/s; a track past this is sampled fast
local ZONE_REFRESH_M = 30.0         -- the zone is looked up again after this walk
local OWN_VEHICLE_MS = 500

local tracks = HumalikeWorldTrack.tracks
local vehicleInfo, forgetVehicle, seatOf

local function returnDistance()
    local vehicles = Config and Config.Vehicles
    return vehicles and vehicles.ReturnDistance or 60.0
end

local function bump(track)
    track.version = track.version + 1
    HumalikeWorldTrack.changeRevision = HumalikeWorldTrack.changeRevision + 1
end

vehicleInfo = function(vehicle) return HumalikeWorldVehicle.Info(vehicle) end
forgetVehicle = function(vehicle) HumalikeWorldVehicle.Forget(vehicle) end
seatOf = function(vehicle, ped) return HumalikeWorldVehicle.SeatOf(vehicle, ped) end

local function sampleVehicle(track, now)
    local ped = track.ped
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        if track.vehicle then
            forgetVehicle(track.vehicle)
            track.vehicle, track.vehicleState, track.seat = nil, nil, nil
            bump(track)
        end
        track.vehicleAt = now
        return
    end
    local networkId, kind = vehicleInfo(vehicle)
    local seat = track.seat
    if vehicle ~= track.vehicle or seat == nil or now - track.seatAt >= SLOW_MS then
        seat = seatOf(vehicle, ped)
        track.seatAt = now
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
    track.vehicleAt = now
end

-- A population driver's own car, from the bag it was spawned with. The bag is
-- read once per track: it is written at spawn and never changes.
local function sampleOwnVehicle(track, now)
    track.ownAt = now
    local networkId = track.ownNet
    if networkId == nil then
        networkId = Entity(track.ped).state.humalike_vehicle_net
        if type(networkId) ~= 'number' or networkId <= 0 then networkId = false end
        track.ownNet = networkId
    end
    local own = nil
    if networkId and NetworkDoesEntityExistWithNetworkId(networkId) then
        local vehicle = NetworkGetEntityFromNetworkId(networkId)
        if vehicle and vehicle > 0 and DoesEntityExist(vehicle) then
            local at = GetEntityCoords(vehicle)
            local dx, dy, dz = at.x - track.x, at.y - track.y, at.z - track.z
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            local _, kind = vehicleInfo(vehicle)
            own = {
                network_id = networkId,
                distance_m = distance,
                in_reach = distance <= returnDistance(),
                kind = kind,
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

-- An ambient body is reported under its npc id only while this client still
-- holds that lease on that ped; a handle reused by another entity shows up as
-- a changed network id or a lease pointing elsewhere.
local function identityMatches(track)
    local entry, ped = track.entry, track.ped
    if NetworkGetNetworkIdFromEntity(ped) ~= entry.networkId then return false end
    if entry.kind ~= 'ambient' then return true end
    return AmbientPeds ~= nil and AmbientPeds[track.npcId] == ped
end

local function sample(track, now, px, py, pz)
    local ped = track.ped
    if not DoesEntityExist(ped) then
        if track.exists then
            track.exists = false
            track.dist2 = math.huge
            bump(track)
        end
        track.sampledAt, track.nextAt = now, now + SLOW_MS
        return
    end
    local at = GetEntityCoords(ped)
    local x, y, z = at.x, at.y, at.z
    local dx, dy, dz = x - track.x, y - track.y, z - track.z
    local moved2 = dx * dx + dy * dy + dz * dz
    local elapsed = (now - track.sampledAt) / 1000.0
    if track.exists and elapsed > 0 then
        track.speed = math.sqrt(moved2) / elapsed
    else
        track.speed = 0.0
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
    if now - track.identityAt >= SLOW_MS or track.identityAt == 0 then
        track.identityAt = now
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
    if near or track.vehicle or track.ownNet or now - track.vehicleAt >= SLOW_MS then
        sampleVehicle(track, now)
    end
    if track.ownNet ~= false and (track.ownNet == nil or now - track.ownAt >= OWN_VEHICLE_MS) then
        sampleOwnVehicle(track, now)
    end

    local interval
    if near then
        interval = NEAR_MS
    elseif track.dist2 <= MID_M * MID_M then
        interval = MID_MS
    else
        interval = FAR_MS
    end
    if track.speed > MOVING_SPEED and interval > FAST_MOVING_MS then interval = FAST_MOVING_MS end
    track.nextAt = now + interval
end

local function newTrack(npcId, entry)
    return {
        npcId = npcId,
        entry = entry,
        ped = entry.entity,
        generation = entry.generation,
        version = 0,
        exists = false,
        x = 0.0, y = 0.0, z = 0.0, dist2 = math.huge, speed = 0.0,
        sampledAt = 0, nextAt = 0,
        identityOk = true, identityAt = 0,
        heading = 0.0,
        zone = nil, zoneX = 0.0, zoneY = 0.0,
        vehicle = nil, vehicleState = nil, seat = nil, seatAt = 0, vehicleAt = 0,
        ownNet = nil, ownVehicle = nil, ownAt = 0,
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
            if track and track.ped == entry.entity then
                -- Same ped, new registration (token, activity): keep the samples.
                fresh.exists, fresh.x, fresh.y, fresh.z = track.exists, track.x, track.y, track.z
                fresh.dist2, fresh.sampledAt = track.dist2, track.sampledAt
                fresh.zone, fresh.zoneX, fresh.zoneY = track.zone, track.zoneX, track.zoneY
                fresh.ownNet = track.ownNet
                fresh.version = track.version + 1
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

-- One pass: tracks that are due are sampled. Exposed for the tests and for a
-- consumer that needs the cache fresh right now.
function HumalikeWorldTrack.Sample(now, px, py, pz)
    syncRegistry()
    HumalikeWorldTrack.playerX, HumalikeWorldTrack.playerY, HumalikeWorldTrack.playerZ = px, py, pz
    local nearest2, sampled = math.huge, 0
    for _, track in pairs(tracks) do
        if now >= track.nextAt then
            sample(track, now, px, py, pz)
            sampled = sampled + 1
        elseif track.exists then
            -- The player moved since this track was sampled; keep its distance current.
            local ex, ey, ez = track.x - px, track.y - py, track.z - pz
            track.dist2 = ex * ex + ey * ey + ez * ez
        end
        if track.dist2 < nearest2 then nearest2 = track.dist2 end
    end
    HumalikeWorldTrack.nearest2 = nearest2
    return sampled
end

function HumalikeWorldTrack.Get(npcId)
    return tracks[npcId]
end

-- True when some live track is within `radius` metres of the player.
function HumalikeWorldTrack.AnyWithin(radius)
    return HumalikeWorldTrack.nearest2 <= radius * radius
end

function HumalikeWorldTrack.Start()
    CreateThread(function()
        while true do
            Wait(TICK_MS)
            local ped = PlayerPedId()
            if ped and ped > 0 then
                local at = GetEntityCoords(ped)
                HumalikeWorldTrack.Sample(GetGameTimer(), at.x, at.y, at.z)
            end
        end
    end)
end
