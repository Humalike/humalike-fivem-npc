HumalikeWorldVehicle = {}

function HumalikeWorldVehicle.StreamState(ped)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle <= 0 or not DoesEntityExist(vehicle)
        or not NetworkGetEntityIsNetworked(vehicle) then return nil end
    local networkId = tonumber(NetworkGetNetworkIdFromEntity(vehicle))
    if not networkId or networkId <= 0 then return nil end
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then
            return { network_id = networkId, seat = seat }
        end
    end
    return nil
end
