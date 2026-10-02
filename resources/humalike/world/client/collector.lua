HumalikeWorldCollector = {
    bootId = nil,
    sequence = 0,
    listenerSequence = 0,
    latest = nil,
    listener = nil,
    voiceMode = 2,
    listenerDemand = false,
}

-- The listener is announced when the ear moved or turned, or every heartbeat.
local LISTENER_MOVE_THRESHOLD = 0.05 -- metres
local LISTENER_TURN_MIN_DOT = math.cos(math.rad(1.0))
local LISTENER_HEARTBEAT_MS = 1000
-- With nothing spatial playing in the NUI the ear is sampled this often instead.
local LISTENER_IDLE_MS = 250
local lastAnnouncedListener = nil

-- In-resource readers of the motion and listener samples are called directly
-- with the one sample table; they read it and never keep or change it.
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

local function listenerChanged(now, px, py, pz, fx, fy, fz)
    local last = lastAnnouncedListener
    if not last then return true end
    if now - last.clientTimeMs >= LISTENER_HEARTBEAT_MS then return true end
    local q = last.position
    if math.abs(px - q.x) > LISTENER_MOVE_THRESHOLD or math.abs(py - q.y) > LISTENER_MOVE_THRESHOLD
        or math.abs(pz - q.z) > LISTENER_MOVE_THRESHOLD then return true end
    local g = last.forward
    return fx * g.x + fy * g.y + fz * g.z < LISTENER_TURN_MIN_DOT
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

local function vec(value)
    return { x = value.x + 0.0, y = value.y + 0.0, z = value.z + 0.0 }
end

local function voiceDistance()
    local proximity = LocalPlayer and LocalPlayer.state and LocalPlayer.state.proximity
    local distance = type(proximity) == 'table' and tonumber(proximity.distance)
        or WorldConfig.collector.defaultVoiceDistance
    return math.min(WorldConfig.collector.maxVoiceDistance, math.max(0.0, distance))
end

function HumalikeWorldCollector.Sample(ped, now, position, velocity)
    position = position or GetEntityCoords(ped)
    velocity = velocity or GetEntityVelocity(ped)
    HumalikeWorldCollector.sequence = HumalikeWorldCollector.sequence + 1
    local sample = {
        v = WorldConfig.protocolVersion,
        type = 'player_motion',
        bootId = HumalikeWorldCollector.bootId,
        sequence = HumalikeWorldCollector.sequence,
        clientTimeMs = now,
        position = vec(position),
        velocity = vec(velocity),
        heading = GetEntityHeading(ped) + 0.0,
        vehicle = HumalikeWorldVehicle.StreamState(ped, now),
        effectiveVoiceDistance = voiceDistance(),
        voiceMode = HumalikeWorldCollector.voiceMode,
        zone = GetNameOfZone(position.x, position.y, position.z),
        flags = {
            dead = IsEntityDead(ped),
            paused = IsPauseMenuActive(),
        },
    }
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

-- The NUI says whether anything spatial is playing; only then is the ear
-- worth sampling thirty times a second.
function HumalikeWorldCollector.SetListenerDemand(active)
    HumalikeWorldCollector.listenerDemand = active == true
end

function HumalikeWorldCollector.SampleListener(now, ped, position)
    ped = ped or PlayerPedId()
    if not ped or ped <= 0 then return nil end
    position = position or GetEntityCoords(ped)
    local rotation = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(rotation.x), math.rad(rotation.z)
    local cosPitch = math.abs(math.cos(pitch))
    local fx, fy, fz = -math.sin(yaw) * cosPitch, math.cos(yaw) * cosPitch, math.sin(pitch)
    HumalikeWorldCollector.listenerSequence = HumalikeWorldCollector.listenerSequence + 1
    local listener = {
        v = 1,
        sequence = HumalikeWorldCollector.listenerSequence,
        clientTimeMs = now,
        position = { x = position.x + 0.0, y = position.y + 0.0, z = position.z + 0.0 },
        forward = { x = fx, y = fy, z = fz },
    }
    HumalikeWorldCollector.listener = listener
    if listenerChanged(now, position.x, position.y, position.z, fx, fy, fz) then
        lastAnnouncedListener = listener
        publish('listener', listener)
    end
    return listener
end

function HumalikeWorldCollector.Start()
    HumalikeWorldCollector.bootId = uuid()
    CreateThread(function()
        while true do
            local ped = PlayerPedId()
            if ped and ped > 0 then
                HumalikeWorldCollector.SampleListener(GetGameTimer(), ped, GetEntityCoords(ped))
            end
            Wait(HumalikeWorldCollector.listenerDemand
                and WorldConfig.collector.listenerIntervalMs or LISTENER_IDLE_MS)
        end
    end)

    CreateThread(function()
        local lastMotionAt, lastPosition = 0, nil
        local pollMs = math.max(50, math.min(100,
            tonumber(WorldConfig.collector.movingIntervalMs) or 100))
        while true do
            local now, ped = GetGameTimer(), PlayerPedId()
            if ped and ped > 0 then
                local position, velocity = GetEntityCoords(ped), GetEntityVelocity(ped)
                local moving = #velocity > WorldConfig.collector.movementThreshold
                local interval = moving and WorldConfig.collector.movingIntervalMs
                    or WorldConfig.collector.idleIntervalMs
                local changed = not lastPosition
                    or #(position - lastPosition) > WorldConfig.collector.positionThreshold
                if now - lastMotionAt >= interval or changed
                    and now - lastMotionAt >= WorldConfig.collector.movingIntervalMs then
                    lastMotionAt, lastPosition = now, position
                    HumalikeWorldCollector.Sample(ped, now, position, velocity)
                end
            end
            Wait(pollMs)
        end
    end)
end
