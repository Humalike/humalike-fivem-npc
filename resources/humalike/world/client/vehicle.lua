HumalikeWorldVehicle = {}

-- A bicycle is its own kind: the edge plans for a cyclist as for a
-- pedestrian, for a car or motorbike as for a motorist.
local function kindOf(vehicle)
    local model = GetEntityModel(vehicle)
    if IsThisModelABicycle(model) then return 'bicycle' end
    return IsThisModelABike(model) and 'bike' or 'car'
end

local function networkIdOf(vehicle)
    if not vehicle or vehicle <= 0 or not DoesEntityExist(vehicle)
        or not NetworkGetEntityIsNetworked(vehicle) then return nil end
    local networkId = tonumber(NetworkGetNetworkIdFromEntity(vehicle))
    if not networkId or networkId <= 0 then return nil end
    return networkId
end

function HumalikeWorldVehicle.StreamState(ped)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    local networkId = networkIdOf(vehicle)
    if not networkId then return nil end
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return { network_id = networkId, seat = seat, kind = kindOf(vehicle) }
        end
    end
    return nil
end

-- The vehicle a population driver was spawned with, wherever the body stands
-- now: the edge tells the NPC where its own car is, so "get back in your car"
-- means this one and never the player's. Nil once the car is gone.
function HumalikeWorldVehicle.OwnState(ped)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end
    local networkId = Entity(ped).state.humalike_vehicle_net
    if type(networkId) ~= 'number' or networkId <= 0
        or not NetworkDoesEntityExistWithNetworkId(networkId) then return nil end
    local vehicle = NetworkGetEntityFromNetworkId(networkId)
    if not vehicle or vehicle <= 0 or not DoesEntityExist(vehicle) then return nil end
    local distance = #(GetEntityCoords(vehicle) - GetEntityCoords(ped))
    return {
        network_id = networkId,
        distance_m = distance,
        -- The walk back is this resource's call (Config.Vehicles.ReturnDistance);
        -- the edge offers the deed only while this says so.
        in_reach = distance <= Config.Vehicles.ReturnDistance,
        kind = kindOf(vehicle),
    }
end
