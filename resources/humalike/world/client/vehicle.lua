HumalikeWorldVehicle = {}

local function kindOf(vehicle)
    return IsThisModelABike(GetEntityModel(vehicle)) and 'bike' or 'car'
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
    return {
        network_id = networkId,
        distance_m = #(GetEntityCoords(vehicle) - GetEntityCoords(ped)),
        kind = kindOf(vehicle),
    }
end
