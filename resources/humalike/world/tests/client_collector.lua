-- The listener is sampled every tick but announced only when it moved or
-- turned, or on the heartbeat, so a still player sends nothing downstream.
WorldConfig = {
    protocolVersion = 1,
    collector = {
        listenerIntervalMs = 33, movingIntervalMs = 100, idleIntervalMs = 1000,
        movementThreshold = 0.08, positionThreshold = 0.15,
        defaultVoiceDistance = 10.0, maxVoiceDistance = 20.0,
    },
}
local copies = 0
HumalikeWorldContracts = { Copy = function(value) copies = copies + 1 return value end }
local announced = {}
local position = { x = 0.0, y = 0.0, z = 0.0 }
local yaw = 0.0
function TriggerEvent() error('samples reach their readers without a local event') end
function GetEntityCoords() return position end
function GetGameplayCamRot() return { x = 0.0, y = 0.0, z = yaw } end
function DoesEntityExist() return true end
function PlayerPedId() return 1 end
function CreateThread() end
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
assert(copies == 4, 'each reader gets its own copy')
print('client_collector: ok')
