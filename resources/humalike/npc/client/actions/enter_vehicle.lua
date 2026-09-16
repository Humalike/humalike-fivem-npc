NpcActions = NpcActions or {}

local MAX_DISTANCE = 12.0
local MAX_SPEED = 2.0
local ATTEMPT_MS = 20000
local attempts = {}

local function stationary(vehicle)
    return #(GetEntityVelocity(vehicle)) < MAX_SPEED
end

local function networked(vehicle)
    return DoesEntityExist(vehicle) and NetworkGetEntityIsNetworked(vehicle)
end

-- Somebody else's car: the body's own is enter_own_vehicle's business and the
-- one it already sits in is not a lift, so a driver told "get in my car" while
-- the player stands beside their parked car finds that car, not its own seat.
local function nearestVehicle(ped, current)
    local npcCoords = GetEntityCoords(ped)
    local own = HumalikeNpcDriving.OwnVehicle(ped)
    local best, bestDistance = nil, MAX_DISTANCE
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if vehicle ~= own and vehicle ~= current and networked(vehicle) and stationary(vehicle) then
            local distance = #(GetEntityCoords(vehicle) - npcCoords)
            if distance < bestDistance
                or (distance == bestDistance and best and vehicle < best) then
                best, bestDistance = vehicle, distance
            end
        end
    end
    return best
end

local function freeSeat(ped, vehicle)
    if GetPedInVehicleSeat(vehicle, -1) ~= 0 then
        for seat = 0, GetVehicleMaxNumberOfPassengers(vehicle) - 1 do
            if GetPedInVehicleSeat(vehicle, seat) == 0 then return seat end
        end
        return nil
    end
    return -1
end

local function done(ped)
    attempts[ped] = nil
    ReleaseActionControl(ped)
end

-- Out of whatever it sits in first, then into the target's free seat.
local function step(ped, attempt)
    local current = GetVehiclePedIsIn(ped, false)
    if current ~= 0 and current ~= attempt.vehicle then
        if not HumalikeNpcDriving.TaskRunning(ped, 'SCRIPT_TASK_LEAVE_VEHICLE') then TaskLeaveVehicle(ped, current, 0) end
        return true
    end
    if HumalikeNpcDriving.TaskRunning(ped, 'SCRIPT_TASK_ENTER_VEHICLE') then return true end
    local seat = freeSeat(ped, attempt.vehicle)
    if not seat then
        print('[humalike-npc] enter_vehicle: no free seat')
        return false
    end
    TaskEnterVehicle(ped, attempt.vehicle, Config.Vehicles.EnterTimeoutMs, seat, 1.0, 1, 0)
    return true
end

NpcActions['enter_vehicle'] = function(ped, params)
    local partner = ActionTargetPed(ped, params, Config.Punch.MaxDistance * 4)
    local partnerVehicle = partner and GetVehiclePedIsIn(partner, false) or 0
    local current = GetVehiclePedIsIn(ped, false)
    local vehicle = partnerVehicle ~= 0 and networked(partnerVehicle)
        and partnerVehicle or nearestVehicle(ped, current)
    if not vehicle or vehicle == current then
        -- Already there, or nothing else to get into within reach.
        if not vehicle then print('[humalike-npc] enter_vehicle: no networked vehicle within reach') end
        done(ped)
        return
    end
    if current ~= 0 and NpcActionDrivesOwnVehicle(ped) then
        HumalikeNpcDriving.Dismiss(ped) -- gives its own car up for the other one
    end
    if current == 0 then ClearPedTasks(ped) end
    MarkActionControl(ped, 'enter_vehicle')
    local attempt = { vehicle = vehicle, startedAt = GetGameTimer() }
    attempts[ped] = attempt
    if not step(ped, attempt) then done(ped) end
end

NpcActionSustain['enter_vehicle'] = function(ped)
    local attempt = attempts[ped]
    -- The seat is the deed: only the TARGET vehicle counts, never the one it
    -- is still climbing out of (that released too early and the population
    -- put the driver straight back behind its own wheel).
    if not attempt or GetVehiclePedIsIn(ped, false) == attempt.vehicle then
        done(ped)
        return
    end
    if not networked(attempt.vehicle) or GetGameTimer() - attempt.startedAt > ATTEMPT_MS then
        done(ped)
        return
    end
    if not step(ped, attempt) then done(ped) end
end
