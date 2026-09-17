local Vec = {}
Vec.__index = Vec
Vec.__sub = function(left, right)
    return setmetatable({ x = left.x - right.x, y = left.y - right.y, z = left.z - right.z }, Vec)
end
Vec.__len = function(value)
    return math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
end

vector3 = function(x, y, z) return setmetatable({ x = x, y = y, z = z }, Vec) end

local entities = {
    [1] = vector3(0, 0, 0),
    [2] = vector3(1, 0, 0),
    [101] = vector3(0, 0, 0),
    [102] = vector3(1, 0, 0),
}
local pedVehicles = { [1] = 101, [2] = 102 }
local networked = { [101] = true, [102] = true }
local networkIds = { [101] = 501, [102] = 502 }
local occupants = { [101] = { [-1] = 1 }, [102] = { [0] = 2 } }

DoesEntityExist = function(entity) return entities[entity] ~= nil end
GetVehiclePedIsIn = function(ped) return pedVehicles[ped] or 0 end
NetworkGetEntityIsNetworked = function(entity) return networked[entity] == true end
NetworkGetNetworkIdFromEntity = function(entity) return networkIds[entity] or 0 end
GetVehicleMaxNumberOfPassengers = function() return 2 end
GetPedInVehicleSeat = function(vehicle, seat) return occupants[vehicle][seat] or 0 end
GetEntityCoords = function(entity) return entities[entity] end
GetEntityVelocity = function() return vector3(0, 0, 0) end
GetEntityHeading = function() return 90.0 end
GetEntityModel = function(entity) return entity == 102 and 456 or 123 end
IsThisModelABike = function(model) return model == 456 end
IsThisModelABicycle = function(model) return model == 789 end
local bags = { [2] = { humalike_vehicle_net = 502 } }
Entity = function(entity) return { state = bags[entity] or {} } end
NetworkDoesEntityExistWithNetworkId = function(networkId) return networkId == 502 end
NetworkGetEntityFromNetworkId = function(networkId) return networkId == 502 and 102 or 0 end
GetNameOfZone = function() return 'TEST' end
RegisterNetEvent = function() end
RegisterNUICallback = function() end
TriggerServerEvent = function() end
SetTimeout = function() end
TriggerEvent = function() end
SendNUIMessage = function() end
CreateThread = function() end
Wait = function() end

Config = { Vehicles = { ReturnDistance = 60.0 } }
WorldConfig = {
    collector = { movementThreshold = 0.1 },
    npcEdge = {
        enabled = true,
        reportRadius = 150,
        maxNpcsPerFrame = 32,
        frameIntervalMs = 200,
        ticketRetryMs = 1000,
    },
}
HumalikeWorldCollector = { bootId = 'boot' }
HumalikeWorldRegistry = {
    entries = {
        ['npc-1'] = {
            npcId = 'npc-1',
            entity = 2,
            entityId = 202,
            networkId = 302,
            modelHash = 123,
            runtimeToken = 'token-npc-1',
            activity = 'idle',
        },
    },
}

dofile('client/vehicle.lua')
dofile('client/npc_edge.lua')

local player = {
    position = vector3(0, 0, 0),
    effectiveVoiceDistance = 8.0,
    vehicle = { networkId = 999, seat = -2 },
}
local frame = HumalikeWorldNpcEdge.BuildPositionsFrame(player, 1, 7)
assert(frame.type == 'positions')
assert(frame.sequence == 7)
assert(frame.player.vehicle.network_id == 501)
assert(frame.player.vehicle.seat == -1)
assert(frame.player.vehicle.networkId == nil)
assert(#frame.npcs == 1)
assert(frame.npcs[1].vehicle.network_id == 502)
assert(frame.npcs[1].vehicle.seat == 0)
assert(frame.player.vehicle.kind == 'car')
assert(frame.npcs[1].vehicle.kind == 'bike', 'the vehicle kind rides along')
GetEntityModel = function(entity) return entity == 101 and 789 or 123 end
assert(HumalikeWorldNpcEdge.BuildPositionsFrame(player, 1, 8).player.vehicle.kind == 'bicycle',
    'a bicycle is reported as its own kind')
GetEntityModel = function(entity) return entity == 102 and 456 or 123 end
assert(frame.npcs[1].own_vehicle.network_id == 502 and frame.npcs[1].own_vehicle.kind == 'bike')
assert(frame.npcs[1].own_vehicle.distance_m == 0, 'seated in it: no distance to its own vehicle')
assert(frame.npcs[1].own_vehicle.in_reach == true)

occupants[101], occupants[102] = { [0] = 1 }, { [-1] = 2 }
frame = HumalikeWorldNpcEdge.BuildPositionsFrame(player, 1, 8)
assert(frame.player.vehicle.seat == 0)
assert(frame.npcs[1].vehicle.seat == -1)

pedVehicles[1], pedVehicles[2] = nil, nil
frame = HumalikeWorldNpcEdge.BuildPositionsFrame(player, 1, 9)
assert(frame.player.vehicle == nil)
assert(frame.npcs[1].vehicle == nil)
assert(frame.npcs[1].own_vehicle.network_id == 502, 'on foot, its own vehicle is still reported')
assert(frame.npcs[1].own_vehicle.distance_m == 0)
entities[2] = vector3(13, 0, 0)
frame = HumalikeWorldNpcEdge.BuildPositionsFrame(player, 1, 10)
assert(frame.npcs[1].own_vehicle.distance_m == 12, 'with how far it has walked from it')
assert(frame.npcs[1].own_vehicle.in_reach == true)
entities[2] = vector3(62, 0, 0)
frame = HumalikeWorldNpcEdge.BuildPositionsFrame(player, 1, 11)
assert(frame.npcs[1].own_vehicle.in_reach == false, 'past the return distance the walk back is off')
entities[2] = vector3(1, 0, 0)
bags[2].humalike_vehicle_net = 777
assert(HumalikeWorldVehicle.OwnState(2) == nil, 'a vehicle that no longer exists is not reported')
bags[2].humalike_vehicle_net = nil
assert(HumalikeWorldVehicle.OwnState(2) == nil, 'a body spawned on foot has none')
assert(HumalikeWorldVehicle.OwnState(1) == nil, 'nor does the player')
bags[2].humalike_vehicle_net = 502

pedVehicles[1] = 101
occupants[101] = {}
assert(HumalikeWorldVehicle.StreamState(1) == nil)
occupants[101][-1] = 1
networked[101] = false
assert(HumalikeWorldVehicle.StreamState(1) == nil)
networked[101] = true
networkIds[101] = 0
assert(HumalikeWorldVehicle.StreamState(1) == nil)

print('client_vehicle: ok')
