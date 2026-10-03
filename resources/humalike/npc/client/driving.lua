HumalikeNpcDriving = HumalikeNpcDriving or {}

local DRIVE_WANDER_TASK = 'SCRIPT_TASK_VEHICLE_DRIVE_WANDER'
local ENTER_TASK = 'SCRIPT_TASK_ENTER_VEHICLE'
local enteredAt = {}
local lost = {} -- the seat went to someone else: the body walks off and is never sent back
local resumed = {} -- told to drive off: the hold loop's brake yields until an explicit stop order
local walkBack = {} -- reclaimed on foot: walks to its car, is never warped into it

local function cfg()
    return Config.Vehicles
end

local function vehicleOf(state)
    local networkId = state.humalike_vehicle_net
    if type(networkId) ~= 'number' or networkId <= 0
        or not NetworkDoesEntityExistWithNetworkId(networkId) then return nil end
    local vehicle = NetworkGetEntityFromNetworkId(networkId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    return vehicle
end

-- A task name is hashed once: the body tick asks this for every driver.
local taskHashes = {}

function HumalikeNpcDriving.TaskRunning(ped, taskName)
    local hash = taskHashes[taskName]
    if not hash then
        hash = GetHashKey(taskName)
        taskHashes[taskName] = hash
    end
    return GetScriptTaskStatus(ped, hash) <= 1
end

local function taskDropped(ped, taskName)
    return not HumalikeNpcDriving.TaskRunning(ped, taskName)
end

-- The one answer to "may this body take that driver seat": nobody else in
-- it and no player anywhere in the vehicle.
function HumalikeNpcDriving.SeatFree(vehicle, ped)
    local occupant = GetPedInVehicleSeat(vehicle, -1)
    return (occupant == 0 or occupant == ped) and not HumalikePlayerInVehicle(vehicle)
end

-- Dismissal lives on the ped, not on this client: the owner that told it to
-- get out is not always the owner that next runs Apply -- a migration in
-- between used to warp it straight back into the car it just left.
local DISMISSED_KEY = 'humalike_driver_dismissed'
local function dismissed(ped, state)
    return lost[ped] == true or (state or Entity(ped).state)[DISMISSED_KEY] == true
end

local function drive(ped, vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    TaskVehicleDriveWander(ped, vehicle, cfg().DriveSpeed, cfg().DriveStyle)
end

-- True while the body is still after its seat; false once it gave the vehicle up.
local function enter(ped, vehicle, now)
    if not HumalikeNpcDriving.SeatFree(vehicle, ped) then
        lost[ped] = true
        TaskWanderStandard(ped, 10.0, 10)
        return false
    end
    local timeout = cfg().EnterTimeoutMs
    if enteredAt[ped] and now - enteredAt[ped] < timeout then return true end
    enteredAt[ped] = now
    TaskEnterVehicle(ped, vehicle, timeout, -1, 1.0, 1, 0)
    return true
end

-- True for a population driver sitting at the wheel of its own car: the
-- actions treat it as a driver, not as a passenger who followed a player in.
function HumalikeNpcDriving.DrivesOwnVehicle(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return false end
    local state = Entity(ped).state
    return state.humalike_body_behaviour == 'drive'
        and state.humalike_vehicle_net == NetworkGetNetworkIdFromEntity(vehicle)
        and GetPedInVehicleSeat(vehicle, -1) == ped
end

-- The driver left its car on purpose (got out, took a player's car, went on
-- foot with a player): the car is done with; it never gets back in on its own.
function HumalikeNpcDriving.Dismiss(ped)
    lost[ped] = true
    resumed[ped] = nil
    if DoesEntityExist(ped) then Entity(ped).state:set(DISMISSED_KEY, true, true) end
end

-- Told to get back in: the car is its own again, and once seated the
-- population's Apply/Refresh put it back on the road. It walks there: the
-- spawn-time warp is for a driver born beside its car, not for one that
-- got out in front of a player.
function HumalikeNpcDriving.Reclaim(ped)
    lost[ped] = nil
    walkBack[ped] = true
    if DoesEntityExist(ped) then Entity(ped).state:set(DISMISSED_KEY, nil, true) end
end

-- The car this body was spawned driving, wherever it stands now; nil once gone.
function HumalikeNpcDriving.OwnVehicle(ped)
    if not DoesEntityExist(ped) then return nil end
    return vehicleOf(Entity(ped).state)
end

-- The same car when the body could still walk back to it and take the wheel:
-- standing within the return distance, seat free. Nil plus the reason otherwise.
function HumalikeNpcDriving.OwnVehicleInReach(ped)
    local vehicle = HumalikeNpcDriving.OwnVehicle(ped)
    if not vehicle then return nil, 'no vehicle of its own' end
    if #(GetEntityCoords(vehicle) - GetEntityCoords(ped)) > cfg().ReturnDistance then
        return nil, 'own vehicle out of reach'
    end
    if not HumalikeNpcDriving.SeatFree(vehicle, ped) then return nil, 'own vehicle taken' end
    return vehicle
end

-- Back on the road from wherever it stopped. The server drops its hold with
-- the same action, but that news lands a tick later than this call: without
-- the grace the hold loop braked the car straight after the drive task and
-- the driver told to leave sat there saying it was halfway down the block.
function HumalikeNpcDriving.Resume(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return false end
    resumed[ped] = true
    drive(ped, vehicle)
    return true
end

-- Riders are meant to be in vehicles, so only death and ragdoll count.
function HumalikeNpcDriving.Incapacitated(ped)
    return IsEntityDead(ped) or IsPedRagdoll(ped)
end

-- Issues the driver's task from scratch. False leaves the body to the
-- population's wander: on foot with no vehicle to get back to.
-- A driver standing (or lying) right by its free car is put in the seat at
-- once; a warp that missed at spawn is not a walk-and-open-the-door job.
local function warpIn(ped, vehicle)
    if walkBack[ped] then return false end
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > cfg().WarpDistance then return false end
    if not HumalikeNpcDriving.SeatFree(vehicle, ped) then return false end
    SetPedIntoVehicle(ped, vehicle, -1)
    return true
end

-- Back at its own wheel, however it got there: nothing dismissed any more.
local function reclaimedAtWheel(ped, state)
    lost[ped], walkBack[ped] = nil, nil
    if state[DISMISSED_KEY] then state:set(DISMISSED_KEY, nil, true) end
end

-- Seated in its own car: at the wheel it drives; in a passenger seat (moved
-- over, someone else driving) it is left alone like a passenger elsewhere.
local function seatedOwn(ped, vehicle)
    if not IsPedInVehicle(ped, vehicle, false) then return nil end
    return GetPedInVehicleSeat(vehicle, -1) == ped
end

function HumalikeNpcDriving.Apply(ped, state, now)
    local vehicle = vehicleOf(state)
    if not vehicle then return IsPedInAnyVehicle(ped, false) end
    local atWheel = seatedOwn(ped, vehicle)
    if atWheel ~= nil then
        if not atWheel then return true end
        reclaimedAtWheel(ped, state) -- back at its own wheel after all
        drive(ped, vehicle)
        return true
    end
    if dismissed(ped, state) then return IsPedInAnyVehicle(ped, false) end
    if warpIn(ped, vehicle) then
        drive(ped, vehicle)
        return true
    end
    return enter(ped, vehicle, now)
end

-- Re-issues only what dropped: the drive task once it is gone, the seat once
-- the enter task is over and the attempt window has passed.
function HumalikeNpcDriving.Refresh(ped, state, now)
    local vehicle = vehicleOf(state)
    if not vehicle then return IsPedInAnyVehicle(ped, false) end
    local atWheel = seatedOwn(ped, vehicle)
    if atWheel ~= nil then
        if not atWheel then return true end
        reclaimedAtWheel(ped, state)
        if taskDropped(ped, DRIVE_WANDER_TASK) then drive(ped, vehicle) end
        return true
    end
    if dismissed(ped, state) then return IsPedInAnyVehicle(ped, false) end
    if not taskDropped(ped, ENTER_TASK) then return true end
    return enter(ped, vehicle, now)
end

-- Brakes a seated driver; true when it did, so a hold on it (ambient control)
-- leaves the stand-still to us. After Resume the hold loop's REPEAT brakes
-- yield: the server's release lands a tick after the action that resumed the
-- drive, and that stale hold must not stop the car again. A NEW hold (a stop
-- order, the next conversation) passes `force`, brakes at once and ends the
-- yielding.
function HumalikeNpcDriving.Brake(ped, force)
    if not DoesEntityExist(ped) then return false end
    local state = Entity(ped).state
    if state.humalike_body_behaviour ~= 'drive' or not IsPedInAnyVehicle(ped, false) then
        return false
    end
    local vehicle = vehicleOf(state)
    if not vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then return false end
    if force then
        resumed[ped] = nil
    elseif resumed[ped] then
        return true -- told to drive off: the hold is on its way out, keep rolling
    end
    TaskVehicleTempAction(ped, vehicle, cfg().BrakeAction, Config.AmbientControl.StandTaskDurationMs)
    return true
end

function HumalikeNpcDriving.Forget(seen)
    for _, registry in ipairs({ enteredAt, lost, resumed, walkBack }) do
        for ped in pairs(registry) do
            if not seen[ped] then registry[ped] = nil end
        end
    end
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    enteredAt, lost, resumed, walkBack = {}, {}, {}, {}
end)
