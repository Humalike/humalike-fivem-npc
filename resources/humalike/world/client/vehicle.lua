HumalikeWorldVehicle = {}

-- Read once per handle. "Not networked" is never kept: a vehicle can be networked later.
local kinds = {}
local networkIds = {}
local SEAT_RECHECK_MS = 1000
local seats = {} -- ped -> { vehicle, seat, at }
local occupied = {} -- ped -> vehicle

function HumalikeWorldVehicle.Info(vehicle)
    local networkId = networkIds[vehicle]
    if networkId == nil then
        if NetworkGetEntityIsNetworked(vehicle) then
            local value = tonumber(NetworkGetNetworkIdFromEntity(vehicle))
            if value and value > 0 then
                networkId = value
                networkIds[vehicle] = value
            end
        end
        if kinds[vehicle] == nil then
            kinds[vehicle] = IsThisModelABike(GetEntityModel(vehicle)) and 'bike' or 'car'
        end
    end
    return networkId, kinds[vehicle]
end

function HumalikeWorldVehicle.Forget(vehicle)
    networkIds[vehicle] = nil
    kinds[vehicle] = nil
end

function HumalikeWorldVehicle.SeatOf(vehicle, ped)
    for seat = -1, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
        if GetPedInVehicleSeat(vehicle, seat) == ped then return seat end
    end
    return nil
end

local function seatOf(vehicle, ped, now)
    local cached = seats[ped]
    if cached and cached.vehicle == vehicle and now - cached.at < SEAT_RECHECK_MS then
        return cached.seat
    end
    local seat = HumalikeWorldVehicle.SeatOf(vehicle, ped)
    seats[ped] = { vehicle = vehicle, seat = seat, at = now }
    return seat
end

function HumalikeWorldVehicle.StreamState(ped, now)
    local vehicle = GetVehiclePedIsIn(ped, false)
    local previous = occupied[ped]
    if previous and previous ~= vehicle then
        HumalikeWorldVehicle.Forget(previous)
        seats[ped] = nil
    end
    if vehicle == 0 then
        occupied[ped] = nil
        return nil
    end
    occupied[ped] = vehicle
    local networkId, kind = HumalikeWorldVehicle.Info(vehicle)
    if not networkId then return nil end
    local seat = seatOf(vehicle, ped, now or GetGameTimer())
    if not seat then return nil end
    return { networkId = networkId, seat = seat, kind = kind }
end
