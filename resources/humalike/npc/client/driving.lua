HumalikeNpcDriving = HumalikeNpcDriving or {}

local DRIVE_WANDER_TASK = 'SCRIPT_TASK_VEHICLE_DRIVE_WANDER'
local ENTER_TASK = 'SCRIPT_TASK_ENTER_VEHICLE'
local enteredAt = {}
local lost = {} -- the seat went to someone else: the body walks off and is never sent back
local resumedAt = {} -- told to drive off: the hold loop must not brake it again for a moment
local RESUME_GRACE_MS = 5000

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

local function taskDropped(ped, taskName)
    return GetScriptTaskStatus(ped, GetHashKey(taskName)) > 1
end

local function drive(ped, vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    TaskVehicleDriveWander(ped, vehicle, cfg().DriveSpeed, cfg().DriveStyle)
end

-- True while the body is still after its seat; false once it gave the vehicle up.
local function enter(ped, vehicle, now)
    local occupant = GetPedInVehicleSeat(vehicle, -1)
    if (occupant ~= 0 and occupant ~= ped) or HumalikePlayerInVehicle(vehicle) then
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
end

-- Told to get back in: the car is its own again, and once seated the
-- population's Apply/Refresh put it back on the road.
function HumalikeNpcDriving.Reclaim(ped)
    lost[ped] = nil
end

-- The car this body was spawned driving, wherever it stands now; nil once gone.
function HumalikeNpcDriving.OwnVehicle(ped)
    if not DoesEntityExist(ped) then return nil end
    return vehicleOf(Entity(ped).state)
end

-- Back on the road from wherever it stopped. The server drops its hold with
-- the same action, but that news lands a tick later than this call: without
-- the grace the hold loop braked the car straight after the drive task and
-- the driver told to leave sat there saying it was halfway down the block.
function HumalikeNpcDriving.Resume(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return false end
    resumedAt[ped] = GetGameTimer()
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
    if #(GetEntityCoords(ped) - GetEntityCoords(vehicle)) > cfg().WarpDistance then return false end
    local occupant = GetPedInVehicleSeat(vehicle, -1)
    if (occupant ~= 0 and occupant ~= ped) or HumalikePlayerInVehicle(vehicle) then return false end
    SetPedIntoVehicle(ped, vehicle, -1)
    return true
end

function HumalikeNpcDriving.Apply(ped, state, now)
    local vehicle = vehicleOf(state)
    if not vehicle then return IsPedInAnyVehicle(ped, false) end
    if IsPedInVehicle(ped, vehicle, false) then
        lost[ped] = nil -- back at its own wheel after all
        drive(ped, vehicle)
        return true
    end
    if lost[ped] then return IsPedInAnyVehicle(ped, false) end
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
    if IsPedInVehicle(ped, vehicle, false) then
        lost[ped] = nil
        if taskDropped(ped, DRIVE_WANDER_TASK) then drive(ped, vehicle) end
        return true
    end
    if lost[ped] then return IsPedInAnyVehicle(ped, false) end
    if not taskDropped(ped, ENTER_TASK) then return true end
    return enter(ped, vehicle, now)
end

-- Brakes a seated driver; true when it did, so a hold on it (ambient control)
-- leaves the stand-still to us. The hold loop's repeat brakes yield for a
-- moment after Resume; an explicit stop order (`force`) never does.
function HumalikeNpcDriving.Brake(ped, force)
    if not DoesEntityExist(ped) then return false end
    local state = Entity(ped).state
    if state.humalike_body_behaviour ~= 'drive' or not IsPedInAnyVehicle(ped, false) then
        return false
    end
    local vehicle = vehicleOf(state)
    if not vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then return false end
    if force then
        resumedAt[ped] = nil
    elseif resumedAt[ped] and GetGameTimer() - resumedAt[ped] < RESUME_GRACE_MS then
        return true -- just told to drive off: the hold is on its way out, keep rolling
    end
    TaskVehicleTempAction(ped, vehicle, cfg().BrakeAction, Config.AmbientControl.StandTaskDurationMs)
    return true
end

function HumalikeNpcDriving.Forget(seen)
    for _, registry in ipairs({ enteredAt, lost, resumedAt }) do
        for ped in pairs(registry) do
            if not seen[ped] then registry[ped] = nil end
        end
    end
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    enteredAt, lost, resumedAt = {}, {}, {}
end)
