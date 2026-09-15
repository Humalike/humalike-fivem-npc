HumalikeNpcDriving = HumalikeNpcDriving or {}

local DRIVE_WANDER_TASK = 'SCRIPT_TASK_VEHICLE_DRIVE_WANDER'
local ENTER_TASK = 'SCRIPT_TASK_ENTER_VEHICLE'
local enteredAt = {}
local lost = {} -- the seat went to someone else: the body walks off and is never sent back

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

-- Riders are meant to be in vehicles, so only death and ragdoll count.
function HumalikeNpcDriving.Incapacitated(ped)
    return IsEntityDead(ped) or IsPedRagdoll(ped)
end

-- Issues the driver's task from scratch. False leaves the body to the
-- population's wander: on foot with no vehicle to get back to.
function HumalikeNpcDriving.Apply(ped, state, now)
    local vehicle = vehicleOf(state)
    if not vehicle then return IsPedInAnyVehicle(ped, false) end
    if IsPedInVehicle(ped, vehicle, false) then
        drive(ped, vehicle)
        return true
    end
    if lost[ped] then return false end
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
    if lost[ped] then return false end
    if not taskDropped(ped, ENTER_TASK) then return true end
    return enter(ped, vehicle, now)
end

-- Brakes a seated driver; true when it did, so a hold on it (ambient control)
-- leaves the stand-still to us.
function HumalikeNpcDriving.Brake(ped)
    if not DoesEntityExist(ped) then return false end
    local state = Entity(ped).state
    if state.humalike_body_behaviour ~= 'drive' or not IsPedInAnyVehicle(ped, false) then
        return false
    end
    local vehicle = vehicleOf(state)
    if not vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then return false end
    TaskVehicleTempAction(ped, vehicle, cfg().BrakeAction, Config.AmbientControl.StandTaskDurationMs)
    return true
end

function HumalikeNpcDriving.Forget(seen)
    for _, registry in ipairs({ enteredAt, lost }) do
        for ped in pairs(registry) do
            if not seen[ped] then registry[ped] = nil end
        end
    end
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    enteredAt, lost = {}, {}
end)
