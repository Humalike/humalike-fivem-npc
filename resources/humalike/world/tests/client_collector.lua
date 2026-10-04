-- The listener is sampled every tick but announced only when it moved or
-- turned, or on the heartbeat, so a still player sends nothing downstream.
WorldConfig = {
    protocolVersion = 1,
    collector = {
        listenerIntervalMs = 33, movingIntervalMs = 200, idleIntervalMs = 1000,
        movementThreshold = 0.08, positionThreshold = 0.15,
        defaultVoiceDistance = 10.0, maxVoiceDistance = 20.0,
    },
}
HumalikeWorldContracts = { Copy = function() error('readers get the sample itself, not a copy') end }
local announced = {}
local position = { x = 0.0, y = 0.0, z = 0.0 }
local yaw = 0.0
function TriggerEvent() error('samples reach their readers without a local event') end
function GetEntityCoords() return position end
function GetGameplayCamRot() return { x = 0.0, y = 0.0, z = yaw } end
function DoesEntityExist() return true end
function PlayerPedId() return 1 end
function CreateThread() end
dofile('client/pulse.lua')
dofile('client/collector.lua')
assert(HumalikeWorldCollector.Subscribe('listener', function(payload)
    announced[#announced + 1] = payload
end))
assert(not HumalikeWorldCollector.Subscribe('unknown', function() end))

local now = 0
local function sample() now = now + 33; HumalikeWorldCollector.SampleListener(now, 1, position) end
for _ = 1, 10 do sample() end
assert(#announced == 1, 'a still ear is announced once')
assert(HumalikeWorldCollector.listener.sequence == 10, 'yet sampled every tick for local readers')
now = now + 1000
sample()
assert(#announced == 2, 'and again on the heartbeat')
position = { x = 0.02, y = 0.0, z = 0.0 }
sample()
assert(#announced == 2, 'a two-centimetre drift is noise')
position = { x = 0.2, y = 0.0, z = 0.0 }
sample()
assert(#announced == 3, 'a step is announced')
yaw = 0.5
sample()
assert(#announced == 3, 'half a degree is noise')
yaw = 3.0
sample()
assert(#announced == 4 and announced[4].position.x == 0.2, 'a turn is announced')
assert(announced[4] == HumalikeWorldCollector.listener, 'readers see the one sample table')

-- The heartbeat is a beat of the pulse's clock, wherever the last announcement
-- was in it, so it leaves with the other once-a-second messages.
now = 5990
HumalikeWorldCollector.SampleListener(now, 1, position, 5)
local before = #announced
HumalikeWorldCollector.SampleListener(6000, 1, position, 6)
assert(#announced == before + 1, 'ten milliseconds later, but a new beat')
HumalikeWorldCollector.SampleListener(6250, 1, position, 6)
HumalikeWorldCollector.SampleListener(6750, 1, position, 6)
assert(#announced == before + 1)
HumalikeWorldCollector.SampleListener(7000, 1, position, 7)
assert(#announced == before + 2)

-- Motion: a moving player is sampled every movingIntervalMs, a still one when
-- its position changed and once in every idle second of the game clock.
local Vec = {}
Vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, Vec) end
Vec.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vec) end
local bagReads, serverIdReads = 0, 0
local proximity = { distance = 4.0 }
LocalPlayer = setmetatable({}, { __index = function(_, key)
    if key ~= 'state' then return nil end
    bagReads = bagReads + 1
    return setmetatable({}, { __index = function(_, field) return field == 'proximity' and proximity or nil end })
end })
function GetPlayerServerId() serverIdReads = serverIdReads + 1 return 7 end
function PlayerId() return 0 end
function GetEntityHeading() return 90.0 end
function GetNameOfZone() return 'DOWNT' end
function IsEntityDead() return false end
function IsPauseMenuActive() return false end
HumalikeWorldVehicle = { StreamState = function() return nil end }
local motions = {}
assert(HumalikeWorldCollector.Subscribe('motion', function(state) motions[#motions + 1] = state.clientTimeMs end))
local still, walking = vec(0, 0, 0), vec(1.5, 0, 0)
local at = vec(10, 0, 0)
-- poll(now, position, velocity): the step and the beat are taken from the time, as the pulse numbers them.
local function poll(time, position, velocity)
    return HumalikeWorldCollector.PollMotion(time, 1, position, velocity, time - time % 50)
end
assert(poll(20000, at, still) == false and #motions == 1, 'the first poll samples')
local first = HumalikeWorldCollector.latest
assert(first.position.x == 10 and first.effectiveVoiceDistance == 4.0 and first.zone == 'DOWNT'
    and first.flags.dead == false and first.type == 'player_motion' and first.clientTimeMs == 20000)
poll(20250, at, still)
poll(20750, at, still)
assert(#motions == 1, 'a still player is not sampled between heartbeats')
poll(21003, at, still)
assert(#motions == 2 and motions[2] == 21003, 'the heartbeat: once in every second, stamped with the real time')
assert(poll(21100, at, walking) == true and #motions == 2, 'a first step within the 200 ms of the last sample waits')
at = vec(10.3, 0, 0)
poll(21200, at, walking)
assert(#motions == 3, 'moving: a sample every 200 ms')
poll(21316, vec(10.45, 0, 0), walking)
assert(#motions == 3)
poll(21400, vec(10.6, 0, 0), walking)
assert(#motions == 4, 'a late frame does not stretch the cadence')
poll(21500, vec(10.9, 0, 0), still)
assert(#motions == 4, 'the stop itself waits out the 200 ms')
poll(21750, vec(10.9, 0, 0), still)
assert(#motions == 5, 'then the last position is sent')
poll(22000, vec(10.9, 0, 0), still)
assert(#motions == 6, 'and the heartbeat is back on the second')
assert(HumalikeWorldCollector.latest == first, 'one sample table, rewritten in place')
assert(bagReads == 1 and serverIdReads == 1, 'the player state bag is looked up once')
proximity = { distance = 500.0 }
poll(23000, vec(10.9, 0, 0), still)
assert(HumalikeWorldCollector.latest.effectiveVoiceDistance == 20.0, 'yet its value is read on every sample, and capped')

-- The ear is sampled fast only while the NUI has an NPC speaking.
function GetGameTimer() return now end
function GetEntityVelocity() return still end
function SendNuiMessage() end
position = vec(0.2, 0.0, 0.0)
HumalikeWorldCollector.Start()
local function samples() return HumalikeWorldCollector.listenerSequence end
local base = samples()
now = 30000
HumalikePulse.Run(now)
assert(samples() == base + 1, 'the listener job samples on its first pulse')
now = 30100
HumalikePulse.Run(now)
assert(samples() == base + 1)
now = 30250
HumalikePulse.Run(now)
assert(samples() == base + 2, 'idle: four samples a second')
HumalikeWorldCollector.SetListenerDemand(true)
now = 30500
HumalikePulse.Run(now)
now = 30533
HumalikePulse.Run(now)
now = 30566
HumalikePulse.Run(now)
assert(samples() == base + 5, 'with an NPC speaking: every listenerIntervalMs')
HumalikeWorldCollector.SetListenerDemand(false)
now = 30600
HumalikePulse.Run(now)
now = 30700
HumalikePulse.Run(now)
assert(samples() == base + 6, 'and back to the idle cadence')

-- The ear on demand (a push-to-talk press): read from the camera as it is now,
-- on the pulse's beat, so nothing is announced twice within a heartbeat.
local announcedBefore = #announced
yaw = 90.0
local fresh = HumalikeWorldCollector.RefreshListener(123456)
assert(fresh == HumalikeWorldCollector.listener and math.abs(fresh.forward.x + 1.0) < 1e-6,
    'the listener is sampled at once from the current camera')
assert(#announced == announcedBefore + 1, 'a turn is announced')
HumalikeWorldCollector.RefreshListener(123460)
assert(#announced == announcedBefore + 1, 'the same ear is not announced again')
print('client_collector: ok')
