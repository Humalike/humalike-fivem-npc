-- The tracker samples each registered NPC on a cadence set by its distance,
-- caches what the edge frame, labels, targets and shove detector read, and
-- bumps a version only when something they would report changed.
local natives = {}
local function count(name) natives[name] = (natives[name] or 0) + 1 end
local function total()
    local sum = 0
    for _, n in pairs(natives) do sum = sum + n end
    return sum
end

local positions = { [10] = { x = 5, y = 0, z = 0 }, [20] = { x = 40, y = 0, z = 0 }, [30] = { x = 120, y = 0, z = 0 } }
local exists = { [10] = true, [20] = true, [30] = true, [500] = true }
local netIds = { [10] = 210, [20] = 220, [30] = 230, [500] = 900 }
local pedVehicles = {}
local bags = { [30] = { humalike_vehicle_net = 900 } }
local now = 0

function vector3(x, y, z) return { x = x, y = y, z = z } end
function DoesEntityExist(entity) count('DoesEntityExist') return exists[entity] == true end
function GetEntityCoords(entity) count('GetEntityCoords') return positions[entity] end
function GetEntityHeading() count('GetEntityHeading') return 90.0 end
function GetNameOfZone() count('GetNameOfZone') return 'TEST' end
function NetworkGetNetworkIdFromEntity(entity) count('NetworkGetNetworkIdFromEntity') return netIds[entity] end
function NetworkGetEntityIsNetworked() count('NetworkGetEntityIsNetworked') return true end
function NetworkDoesEntityExistWithNetworkId(id) count('NetworkDoesEntityExistWithNetworkId') return id == 900 end
function NetworkGetEntityFromNetworkId(id) count('NetworkGetEntityFromNetworkId') return id == 900 and 500 or 0 end
function GetVehiclePedIsIn(ped) count('GetVehiclePedIsIn') return pedVehicles[ped] or 0 end
function GetVehicleMaxNumberOfPassengers() count('GetVehicleMaxNumberOfPassengers') return 2 end
function GetPedInVehicleSeat(vehicle, seat) count('GetPedInVehicleSeat') return vehicle == 500 and seat == -1 and 30 or 0 end
function GetEntityModel() count('GetEntityModel') return 123 end
function IsThisModelABike() return false end
function Entity(entity)
    return { state = setmetatable({}, { __index = function(_, key)
        count('GetStateBagValue')
        return (bags[entity] or {})[key]
    end }) }
end
function CreateThread() end
function Wait() end
function PlayerPedId() return 1 end
function GetGameTimer() return now end
Config = { Vehicles = { ReturnDistance = 60.0 } }
AmbientPeds = { ['npc-b'] = 20 }
HumalikeWorldRegistry = { revision = 1, entries = {
    ['npc-a'] = { npcId = 'npc-a', entity = 10, entityId = 110, networkId = 210, modelHash = 1,
        runtimeToken = 'a', kind = 'persistent', activity = 'idle', generation = 1 },
    ['npc-b'] = { npcId = 'npc-b', entity = 20, entityId = 120, networkId = 220, modelHash = 2,
        runtimeToken = 'b', kind = 'ambient', activity = 'idle', generation = 1 },
    ['npc-c'] = { npcId = 'npc-c', entity = 30, entityId = 130, networkId = 230, modelHash = 3,
        runtimeToken = 'c', kind = 'ambient', activity = 'idle', generation = 1 },
} }
positions[500] = { x = 121, y = 0, z = 0 }
AmbientPeds['npc-c'] = 30

dofile('client/vehicle.lua')
dofile('client/track.lua')

now = 1000
local sampled = HumalikeWorldTrack.Sample(now, 0, 0, 0)
assert(sampled == 3 and HumalikeWorldTrack.count == 3, 'every registered NPC is sampled on the first pass')
local a, b, c = HumalikeWorldTrack.Get('npc-a'), HumalikeWorldTrack.Get('npc-b'), HumalikeWorldTrack.Get('npc-c')
assert(a.exists and a.x == 5 and a.dist2 == 25 and a.identityOk and a.zone == 'TEST' and a.heading == 90.0)
assert(b.identityOk, 'an ambient body whose lease points at this ped is itself')
assert(c.ownVehicle and c.ownVehicle.network_id == 900 and c.ownVehicle.distance_m == 1
    and c.ownVehicle.in_reach == true, 'a driver\'s own car is read from its bag once')
assert(natives.GetStateBagValue == 3, 'one bag read per track: the car it was spawned with')
assert(HumalikeWorldTrack.nearest2 == 25)
assert(HumalikeWorldTrack.AnyWithin(6) and not HumalikeWorldTrack.AnyWithin(4))
local firstVersionA = a.version

-- Cadence: near every 150 ms, mid every 400 ms, far once a second.
natives = {}
now = 1100
assert(HumalikeWorldTrack.Sample(now, 0, 0, 0) == 0, 'nothing is due 100 ms later')
assert(total() == 0, 'and nothing is paid for')
now = 1160
assert(HumalikeWorldTrack.Sample(now, 0, 0, 0) == 1, 'the near NPC is due after 150 ms')
assert(natives.GetEntityCoords == 1 and natives.DoesEntityExist == 1)
assert(natives.GetNameOfZone == nil and natives.GetEntityHeading == nil and natives.NetworkGetNetworkIdFromEntity == nil,
    'zone, heading and identity are not re-read on a near sample')
assert(a.version == firstVersionA, 'a still NPC does not change version')
now = 1420
natives = {}
assert(HumalikeWorldTrack.Sample(now, 0, 0, 0) == 2, 'near and mid are due by 400 ms')
assert(natives.GetVehiclePedIsIn == 1, 'the vehicle seat is checked per sample only up close')
now = 2050
natives = {}
assert(HumalikeWorldTrack.Sample(now, 0, 0, 0) == 3, 'the far NPC is due after a second')
assert(natives.GetEntityHeading == 2, 'heading is refreshed once a second within 60 m')
assert(natives.NetworkGetNetworkIdFromEntity == 3, 'identity is re-checked once a second')
assert(natives.GetStateBagValue == nil, 'the own-vehicle bag is never read again')

-- Movement bumps the version and speeds the cadence up.
positions[20] = { x = 41.0, y = 0, z = 0 }
now = 2460
local versionB = b.version
HumalikeWorldTrack.Sample(now, 0, 0, 0)
assert(b.version == versionB + 1 and b.x == 41.0, 'a moved NPC changes version')
assert(b.speed > 0.5 and b.nextAt - now == 200, 'a moving mid-range NPC is sampled every 200 ms')
positions[20] = { x = 41.02, y = 0, z = 0 }
now = 2660
versionB = b.version
HumalikeWorldTrack.Sample(now, 0, 0, 0)
assert(b.version == versionB, 'two centimetres is no move')

-- The player moving refreshes distances without sampling.
natives = {}
now = 2700
HumalikeWorldTrack.Sample(now, 4, 0, 0)
assert(a.dist2 == 1 and natives.GetEntityCoords == nil, 'distances follow the player for free')

-- A vehicle: seat state lands in the cache and bumps the version once.
pedVehicles[30] = 500
now = 3100
local versionC = c.version
HumalikeWorldTrack.Sample(now, 0, 0, 0)
assert(c.vehicleState and c.vehicleState.network_id == 900 and c.vehicleState.seat == -1
    and c.vehicleState.kind == 'car' and c.version == versionC + 1)
versionC = c.version
now = 4150
HumalikeWorldTrack.Sample(now, 0, 0, 0)
assert(c.version == versionC, 'an unchanged seat is not a change')
pedVehicles[30] = nil
now = 5200
HumalikeWorldTrack.Sample(now, 0, 0, 0)
assert(c.vehicleState == nil and c.version == versionC + 1, 'leaving the car is a change')

-- Identity: a handle whose network id changed is no longer this NPC.
netIds[10] = 999
now = 6300
HumalikeWorldTrack.Sample(now, 0, 0, 0)
assert(a.identityOk == false, 'a reused handle is caught within a second')
netIds[10] = 210
AmbientPeds['npc-b'] = 77
now = 7400
HumalikeWorldTrack.Sample(now, 0, 0, 0)
assert(b.identityOk == false, 'an ambient lease that moved to another ped is caught')
AmbientPeds['npc-b'] = 20

-- Registry changes: a removed NPC loses its track, a new one gets one.
HumalikeWorldRegistry.entries['npc-a'] = nil
HumalikeWorldRegistry.entries['npc-d'] = { npcId = 'npc-d', entity = 40, entityId = 140, networkId = 240,
    modelHash = 4, runtimeToken = 'd', kind = 'persistent', activity = 'idle', generation = 1 }
positions[40], exists[40], netIds[40] = { x = 1, y = 1, z = 0 }, true, 240
HumalikeWorldRegistry.revision = 2
now = 7500
HumalikeWorldTrack.Sample(now, 0, 0, 0)
assert(HumalikeWorldTrack.Get('npc-a') == nil and HumalikeWorldTrack.Get('npc-d').exists
    and HumalikeWorldTrack.count == 3 and HumalikeWorldTrack.revision == 2)

-- A deleted ped: the track stays (the registry owns the entry) but is not live.
exists[40] = false
now = 7700
HumalikeWorldTrack.Sample(now, 0, 0, 0)
local d = HumalikeWorldTrack.Get('npc-d')
assert(d.exists == false and d.dist2 == math.huge)
print('client_track: ok')
