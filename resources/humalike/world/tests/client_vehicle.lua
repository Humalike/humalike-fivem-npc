-- Vehicle facts are read once per handle; a seat once a second.
local natives = {}
local function count(name) natives[name] = (natives[name] or 0) + 1 end

local pedVehicles = { [1] = 101, [2] = 102 }
local networked = { [101] = true, [102] = true }
local networkIds = { [101] = 501, [102] = 502 }
local occupants = { [101] = { [-1] = 1 }, [102] = { [0] = 2 } }

GetVehiclePedIsIn = function(ped) count('GetVehiclePedIsIn') return pedVehicles[ped] or 0 end
NetworkGetEntityIsNetworked = function(entity) count('NetworkGetEntityIsNetworked') return networked[entity] == true end
NetworkGetNetworkIdFromEntity = function(entity) count('NetworkGetNetworkIdFromEntity') return networkIds[entity] or 0 end
GetVehicleMaxNumberOfPassengers = function() count('GetVehicleMaxNumberOfPassengers') return 2 end
GetPedInVehicleSeat = function(vehicle, seat) count('GetPedInVehicleSeat') return occupants[vehicle][seat] or 0 end
GetEntityModel = function(entity) count('GetEntityModel') return entity == 102 and 456 or 123 end
IsThisModelABike = function(model) return model == 456 end
GetGameTimer = function() return 0 end

dofile('client/vehicle.lua')

local state = HumalikeWorldVehicle.StreamState(1, 1000)
assert(state.networkId == 501 and state.seat == -1 and state.kind == 'car')
state = HumalikeWorldVehicle.StreamState(2, 1000)
assert(state.networkId == 502 and state.seat == 0 and state.kind == 'bike', 'the vehicle kind rides along')
natives = {}
state = HumalikeWorldVehicle.StreamState(1, 1500)
assert(state.seat == -1 and natives.GetVehiclePedIsIn == 1 and natives.GetPedInVehicleSeat == nil
    and natives.NetworkGetNetworkIdFromEntity == nil, 'half a second later only the vehicle handle is asked')
occupants[101] = { [0] = 1 }
state = HumalikeWorldVehicle.StreamState(1, 1900)
assert(state.seat == -1, 'a seat change shows up at the next recheck')
state = HumalikeWorldVehicle.StreamState(1, 2000)
assert(state.seat == 0)

pedVehicles[1] = nil
assert(HumalikeWorldVehicle.StreamState(1, 2100) == nil)
natives = {}
pedVehicles[1] = 101
networkIds[101] = 777
state = HumalikeWorldVehicle.StreamState(1, 2200)
assert(state.networkId == 777 and natives.NetworkGetNetworkIdFromEntity == 1,
    'leaving a vehicle forgets its handle, so a reused handle is read again')

occupants[101] = {}
assert(HumalikeWorldVehicle.StreamState(1, 3300) == nil, 'not in any seat')
occupants[101][-1] = 1
HumalikeWorldVehicle.Forget(101)
networked[101] = false
assert(HumalikeWorldVehicle.StreamState(1, 4400) == nil, 'a local vehicle is not reported')
networked[101] = true
HumalikeWorldVehicle.Forget(101)
networkIds[101] = 0
assert(HumalikeWorldVehicle.StreamState(1, 5500) == nil)
print('client_vehicle: ok')
