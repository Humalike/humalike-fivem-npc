NpcActions = NpcActions or {}

-- A population driver told to get back into ITS OWN car. enter_vehicle is a
-- lift in somebody else's; this one walks the body back to the car it was
-- spawned driving, seats it at the wheel and lets it drive off -- the
-- population resumes the drive the moment the action releases the body.
local attempts = {}

local function cfg()
    return Config.Vehicles
end

local function taskRunning(ped, taskName)
    return GetScriptTaskStatus(ped, GetHashKey(taskName)) <= 1
end

local function done(ped)
    attempts[ped] = nil
    ReleaseActionControl(ped)
end

local function driveOff(ped)
    done(ped)
    HumalikeNpcDriving.Reclaim(ped)
    HumalikeNpcDriving.Resume(ped)
end

-- The body's own car, if it still exists, is free and within walking reach.
local function ownVehicle(ped)
    local vehicle = HumalikeNpcDriving and HumalikeNpcDriving.OwnVehicle(ped) or nil
    if not vehicle then return nil, 'no vehicle of its own' end
    if #(GetEntityCoords(vehicle) - GetEntityCoords(ped)) > cfg().ReturnDistance then
        return nil, 'own vehicle out of reach'
    end
    local occupant = GetPedInVehicleSeat(vehicle, -1)
    if (occupant ~= 0 and occupant ~= ped) or HumalikePlayerInVehicle(vehicle) then
        return nil, 'own vehicle taken'
    end
    return vehicle
end

-- Out of whatever it sits in first, then into its own driver seat.
local function step(ped, vehicle)
    local current = GetVehiclePedIsIn(ped, false)
    if current ~= 0 and current ~= vehicle then
        if not taskRunning(ped, 'SCRIPT_TASK_LEAVE_VEHICLE') then TaskLeaveVehicle(ped, current, 0) end
        return
    end
    if not taskRunning(ped, 'SCRIPT_TASK_ENTER_VEHICLE') then
        TaskEnterVehicle(ped, vehicle, cfg().EnterTimeoutMs, -1, 1.0, 1, 0)
    end
end

NpcActions['enter_own_vehicle'] = function(ped, _params)
    if NpcActionDrivesOwnVehicle(ped) then
        driveOff(ped) -- already at its wheel: "drive off" is the whole deed
        return
    end
    local vehicle, reason = ownVehicle(ped)
    if not vehicle then
        print(('[humalike-npc] enter_own_vehicle: %s'):format(reason))
        done(ped)
        return
    end
    HumalikeNpcDriving.Reclaim(ped)
    if not NpcActionPedInVehicle(ped) then ClearPedTasks(ped) end
    MarkActionControl(ped, 'enter_own_vehicle')
    attempts[ped] = { vehicle = vehicle, startedAt = GetGameTimer() }
    step(ped, vehicle)
end

NpcActionSustain['enter_own_vehicle'] = function(ped)
    if NpcActionDrivesOwnVehicle(ped) then
        driveOff(ped)
        return
    end
    -- A body that migrated mid-walk arrives here with no attempt: rebuild it.
    local attempt = attempts[ped]
    if not attempt then
        local vehicle = ownVehicle(ped)
        if not vehicle then
            done(ped)
            return
        end
        HumalikeNpcDriving.Reclaim(ped)
        attempt = { vehicle = vehicle, startedAt = GetGameTimer() }
        attempts[ped] = attempt
    end
    if GetGameTimer() - attempt.startedAt > cfg().ReturnTimeoutMs then
        done(ped)
        return
    end
    local vehicle = ownVehicle(ped)
    if vehicle ~= attempt.vehicle then
        -- Gone, or somebody took the seat while it walked over: it stays on foot.
        HumalikeNpcDriving.Dismiss(ped)
        done(ped)
        return
    end
    step(ped, vehicle)
end
