-- The collector, the tracker and the edge frame on the one pulse, driven by
-- frames that come at uneven times: what the edge and the NUI receive must
-- not depend on how late a frame was.
math.randomseed(11)
local now = 100000
local sent, sampledAt = {}, {}

local Vec = {}
Vec.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, Vec) end
Vec.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function vec(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vec) end

local positions = { [1] = vec(0, 0, 30), [10] = vec(5, 0, 30), [20] = vec(40, 0, 30), [30] = vec(120, 0, 30) }
local velocity = vec(1.5, 0, 0)

function CreateThread() end
function SetTimeout() end
function Wait() end
function GetGameTimer() return now end
function RegisterNetEvent() end
function RegisterNUICallback() end
function AddEventHandler() end
function TriggerServerEvent() end
function TriggerEvent() end
function SendNUIMessage() end
function SendNuiMessage(raw) sent[#sent + 1] = { at = now, raw = raw } end
function PlayerPedId() return 1 end
function PlayerId() return 0 end
function GetPlayerServerId() return 7 end
function DoesEntityExist(entity) return positions[entity] ~= nil end
function GetEntityCoords(entity)
    if entity == 20 then sampledAt[#sampledAt + 1] = now end
    return positions[entity] or vec(0, 0, 0)
end
function GetEntityVelocity() return velocity end
function GetEntityHeading() return 90.0 end
function GetEntityModel() return 123 end
function AddStateBagChangeHandler() end
function GetGameplayCamRot() return vec(0, 0, 0) end
function GetNameOfZone() return 'DOWNT' end
function GetVehiclePedIsIn() return 0 end
function IsEntityDead() return false end
function IsPauseMenuActive() return false end
function NetworkGetNetworkIdFromEntity(entity) return 200 + entity end
function Entity() return { state = {} } end

WorldConfig = {
    protocolVersion = 1,
    collector = {
        movingIntervalMs = 200, idleIntervalMs = 1000, listenerIntervalMs = 50,
        movementThreshold = 0.08, positionThreshold = 0.15, defaultVoiceDistance = 15.0, maxVoiceDistance = 50.0,
    },
    npcEdge = { enabled = true, frameIntervalMs = 200, ticketRetryMs = 3000, reportRadius = 150.0, maxNpcsPerFrame = 32 },
}
Config = { Vehicles = { ReturnDistance = 60.0 } }
HumalikeWorldRegistry = { revision = 1, entries = {} }
for _, ped in ipairs({ 10, 20, 30 }) do
    local npcId = 'npc-' .. ped
    HumalikeWorldRegistry.entries[npcId] = { npcId = npcId, entity = ped, entityId = 100 + ped, networkId = 200 + ped,
        modelHash = 1, runtimeToken = 't', kind = 'persistent', activity = 'idle', generation = 1 }
end

dofile('client/pulse.lua')
dofile('client/vehicle.lua')
dofile('client/track.lua')
dofile('client/collector.lua')
dofile('client/npc_edge.lua')
-- The voice module forwards every motion sample to the NUI.
HumalikeWorldCollector.Subscribe('motion', function() HumalikePulse.Send('{"type":"game:realtime"}') end)
HumalikeWorldCollector.Start()
HumalikeWorldTrack.Start()
HumalikeWorldNpcEdge.Start()
HumalikeWorldNpcEdge.connected = true

-- A minute at 52-71 fps. The player and the NPC at 40 m walk; the others stand.
local wakeAt, pulses = 0, 0
local stop = now + 60000
while now < stop do
    local dt = math.random(1, 3) == 1 and 1 or math.random(14, 19) -- now and then two wake-ups a millisecond apart
    now = now + dt
    positions[1] = vec(positions[1].x + 1.5 * dt / 1000, 0, 30)
    positions[20] = vec(positions[20].x + 1.5 * dt / 1000, 0, 30)
    -- The scheduler may resume the pulse a millisecond before the time it asked for.
    if now >= wakeAt - math.random(0, 1) then
        pulses = pulses + 1
        wakeAt = now + HumalikePulse.Run(now)
    end
end

local frames, alone, shortest, longest, last = 0, 0, math.huge, 0, nil
for _, message in ipairs(sent) do
    if message.raw:find('"type":"npc_edge_frame"', 1, true) then
        frames = frames + 1
        if not message.raw:find('"type":"game:realtime"', 1, true) then alone = alone + 1 end
        if last then
            shortest, longest = math.min(shortest, message.at - last), math.max(longest, message.at - last)
        end
        last = message.at
    end
end
assert(frames >= 270, ('about five edge frames a second (%d in a minute)'):format(frames))
assert(shortest >= 200, ('two edge frames are never less than the interval apart: the edge keeps one per 200 ms tick (shortest %d)'):format(shortest))
assert(longest <= 240, ('nor more than a frame over it (longest %d)'):format(longest))
assert(alone <= 2, ('the motion sample rides in the message of the edge frame (%d frames went alone)'):format(alone))
assert(#sent <= frames + 4 * 60 + 5, ('edge and motion share a message; the idle listener adds its four a second (%d messages)'):format(#sent))
assert(pulses <= 10 * 60 + 12 * 60, ('one wake-up per grid point (%d pulses)'):format(pulses))

-- (The first interval is the still cadence: its speed is known from the second sample on.)
local widest = 0
for index = 4, #sampledAt do widest = math.max(widest, sampledAt[index] - sampledAt[index - 1]) end
assert(#sampledAt >= 270 and widest <= 240,
    ('a walking NPC at 40 m is sampled every 200 ms however late the frames come (%d samples, widest gap %d)'):format(#sampledAt, widest))
print('client_pulse_stack: ok')
