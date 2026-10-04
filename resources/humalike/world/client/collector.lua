HumalikeWorldCollector = {
    bootId = nil,
    sequence = 0,
    listenerSequence = 0,
    latest = nil,
    listener = nil,
    voiceMode = 2,
    listenerDemand = false,
}

-- The listener is announced when the ear moved or turned, and once in every
-- heartbeat (a beat of the pulse's clock, so the heartbeats of the listener,
-- the motion sample, the edge frame and the labels leave together).
local LISTENER_MOVE_THRESHOLD = 0.05 -- metres
local LISTENER_TURN_MIN_DOT = math.cos(math.rad(1.0))
local LISTENER_HEARTBEAT_MS = 1000
-- With nothing spatial playing in the NUI the ear is sampled this often instead.
local LISTENER_IDLE_MS = 250
-- A still player is polled a quarter as often; the first step shows up
-- within that poll.
local IDLE_POLL_MS = 250

-- In-resource readers of the motion and listener samples are called directly
-- with the one sample table; they read it and never keep or change it. Each
-- table is rewritten in place by the next sample.
local subscribers = { motion = {}, listener = {} }

function HumalikeWorldCollector.Subscribe(kind, callback)
    local list = subscribers[kind]
    if not list or type(callback) ~= 'function' then return false end
    list[#list + 1] = callback
    return true
end

local function publish(kind, value)
    local list = subscribers[kind]
    for index = 1, #list do list[index](value) end
end

local listener = {
    v = 1, sequence = 0, clientTimeMs = 0,
    position = { x = 0.0, y = 0.0, z = 0.0 },
    forward = { x = 0.0, y = 1.0, z = 0.0 },
}
local announcedBeat = nil -- the heartbeat of the last announcement, and what it said
local announcedX, announcedY, announcedZ = 0.0, 0.0, 0.0
local announcedFx, announcedFy, announcedFz = 0.0, 0.0, 0.0

local function listenerChanged(beat, px, py, pz, fx, fy, fz)
    if beat ~= announcedBeat then return true end
    if math.abs(px - announcedX) > LISTENER_MOVE_THRESHOLD or math.abs(py - announcedY) > LISTENER_MOVE_THRESHOLD
        or math.abs(pz - announcedZ) > LISTENER_MOVE_THRESHOLD then return true end
    return fx * announcedFx + fy * announcedFy + fz * announcedFz < LISTENER_TURN_MIN_DOT
end

local function randomHex(length)
    local result = ''
    for _ = 1, length do result = result .. ('%x'):format(math.random(0, 15)) end
    return result
end

local function uuid()
    return randomHex(8) .. '-' .. randomHex(4) .. '-4' .. randomHex(3)
        .. '-8' .. randomHex(3) .. '-' .. randomHex(12)
end

-- The player's state bag is looked up once: LocalPlayer.state builds a new
-- bag object (two natives and a string) on every access.
local playerBag = nil

local function voiceDistance()
    if not playerBag and LocalPlayer then
        local serverId = GetPlayerServerId(PlayerId())
        if serverId and serverId > 0 then playerBag = LocalPlayer.state end
    end
    local proximity = playerBag and playerBag.proximity
    local distance = type(proximity) == 'table' and tonumber(proximity.distance)
        or WorldConfig.collector.defaultVoiceDistance
    return math.min(WorldConfig.collector.maxVoiceDistance, math.max(0.0, distance))
end

-- The zone is looked up again once the player walked this far from where it
-- was last read; zones are hundreds of metres across.
local ZONE_REFRESH_M = 50.0
local zoneName, zoneX, zoneY = nil, 0.0, 0.0

local function zoneOf(position)
    local dx, dy = position.x - zoneX, position.y - zoneY
    if zoneName == nil or dx * dx + dy * dy > ZONE_REFRESH_M * ZONE_REFRESH_M then
        zoneName = GetNameOfZone(position.x, position.y, position.z) or ''
        zoneX, zoneY = position.x, position.y
    end
    return zoneName
end

local sample = {
    v = 1, type = 'player_motion', bootId = nil, sequence = 0, clientTimeMs = 0,
    position = { x = 0.0, y = 0.0, z = 0.0 },
    velocity = { x = 0.0, y = 0.0, z = 0.0 },
    heading = 0.0, vehicle = nil, effectiveVoiceDistance = 0.0, voiceMode = 2, zone = '',
    flags = { dead = false, paused = false },
}

-- `due` is the pulse's schedule time of this sample (the seat cache counts on it).
function HumalikeWorldCollector.Sample(ped, now, position, velocity, due)
    position = position or GetEntityCoords(ped)
    velocity = velocity or GetEntityVelocity(ped)
    HumalikeWorldCollector.sequence = HumalikeWorldCollector.sequence + 1
    sample.v = WorldConfig.protocolVersion
    sample.bootId = HumalikeWorldCollector.bootId
    sample.sequence = HumalikeWorldCollector.sequence
    sample.clientTimeMs = now
    local at, speed = sample.position, sample.velocity
    at.x, at.y, at.z = position.x + 0.0, position.y + 0.0, position.z + 0.0
    speed.x, speed.y, speed.z = velocity.x + 0.0, velocity.y + 0.0, velocity.z + 0.0
    sample.heading = GetEntityHeading(ped) + 0.0
    sample.vehicle = HumalikeWorldVehicle.StreamState(ped, due or now)
    sample.effectiveVoiceDistance = voiceDistance()
    sample.voiceMode = HumalikeWorldCollector.voiceMode
    sample.zone = zoneOf(position)
    sample.flags.dead = IsEntityDead(ped)
    sample.flags.paused = IsPauseMenuActive()
    HumalikeWorldCollector.latest = sample
    publish('motion', sample)
    return sample
end

function HumalikeWorldCollector.SetVoiceMode(mode)
    mode = tonumber(mode)
    if not mode or mode % 1 ~= 0 or mode < 1 or mode > 3 then return false end
    HumalikeWorldCollector.voiceMode = mode
    return true
end

-- The NUI says whether an NPC is being heard; only then is the ear worth
-- sampling twenty times a second.
function HumalikeWorldCollector.SetListenerDemand(active)
    HumalikeWorldCollector.listenerDemand = active == true
end

-- `beat` numbers the heartbeat this sample falls in (the pulse counts them;
-- without one it is taken from the time).
function HumalikeWorldCollector.SampleListener(now, ped, position, beat)
    ped = ped or HumalikePulse.Ped()
    if not ped or ped <= 0 then return nil end
    beat = beat or now // LISTENER_HEARTBEAT_MS
    position = position or GetEntityCoords(ped)
    local rotation = HumalikePulse.CamRot()
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local cosPitch = math.abs(math.cos(pitch))
    local fx, fy, fz = -math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch)
    local px, py, pz = position.x + 0.0, position.y + 0.0, position.z + 0.0
    HumalikeWorldCollector.listenerSequence = HumalikeWorldCollector.listenerSequence + 1
    listener.sequence = HumalikeWorldCollector.listenerSequence
    listener.clientTimeMs = now
    listener.position.x, listener.position.y, listener.position.z = px, py, pz
    listener.forward.x, listener.forward.y, listener.forward.z = fx, fy, fz
    HumalikeWorldCollector.listener = listener
    if listenerChanged(beat, px, py, pz, fx, fy, fz) then
        announcedBeat = beat
        announcedX, announcedY, announcedZ = px, py, pz
        announcedFx, announcedFy, announcedFz = fx, fy, fz
        publish('listener', listener)
    end
    return listener
end

-- The ear as it is right now, outside its own cadence: a push-to-talk press
-- takes the gaze from it.
function HumalikeWorldCollector.RefreshListener(now)
    local ped = HumalikePulse.Ped()
    if not ped or ped <= 0 then return nil end
    return HumalikeWorldCollector.SampleListener(now, ped, HumalikePulse.Coords(ped),
        HumalikePulse.Beat(LISTENER_HEARTBEAT_MS))
end

-- One poll of the player's motion. A sample goes out once per movingIntervalMs
-- while the player moves or a still player's position changed, and once per
-- idleIntervalMs otherwise. `step` and `beat` number those two intervals (the
-- pulse counts them, so a sample leaves on the pulse of the edge frame;
-- without them they are taken from the time). Returns true while moving.
local lastStep, lastBeat, lastPosition = nil, nil, nil

function HumalikeWorldCollector.PollMotion(now, ped, position, velocity, due, step, beat)
    local collector = WorldConfig.collector
    step = step or now // math.max(1, collector.movingIntervalMs)
    beat = beat or now // math.max(1, collector.idleIntervalMs)
    local moving = #velocity > collector.movementThreshold
    local changed = not lastPosition or #(position - lastPosition) > collector.positionThreshold
    if (moving or changed) and step ~= lastStep or not moving and beat ~= lastBeat then
        lastStep, lastBeat, lastPosition = step, beat, position
        HumalikeWorldCollector.Sample(ped, now, position, velocity, due)
    end
    return moving
end

function HumalikeWorldCollector.Start()
    HumalikeWorldCollector.bootId = uuid()
    HumalikePulse.Every('listener', LISTENER_IDLE_MS, function(now)
        local ped = HumalikePulse.Ped()
        if ped and ped > 0 then
            HumalikeWorldCollector.SampleListener(now, ped, HumalikePulse.Coords(ped),
                HumalikePulse.Beat(LISTENER_HEARTBEAT_MS))
        end
        return HumalikeWorldCollector.listenerDemand
            and WorldConfig.collector.listenerIntervalMs or LISTENER_IDLE_MS
    end, 20)

    local pollMs = math.max(50, math.min(100,
        tonumber(WorldConfig.collector.movingIntervalMs) or 100))
    HumalikePulse.Every('motion', IDLE_POLL_MS, function(now, due)
        local ped = HumalikePulse.Ped()
        if not ped or ped <= 0 then return IDLE_POLL_MS end
        local collector = WorldConfig.collector
        local moving = HumalikeWorldCollector.PollMotion(now, ped,
            HumalikePulse.Coords(ped), HumalikePulse.Velocity(ped), due,
            HumalikePulse.Beat(math.max(1, collector.movingIntervalMs)),
            HumalikePulse.Beat(math.max(1, collector.idleIntervalMs)))
        return moving and pollMs or IDLE_POLL_MS
    end, 20)
end
