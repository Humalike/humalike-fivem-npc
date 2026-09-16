
NpcActions = NpcActions or {}

local deadlines = {}
local fromOwn = {} -- got out of its own car: it stays out, whatever stands nearby

local function timeoutMs()
    return Config.Follow.VehicleTaskTimeoutMs or 10000
end

local function forgetStaleDeadlines()
    for ped in pairs(deadlines) do
        if ActionControlledPeds[ped] ~= 'exit_vehicle' then
            deadlines[ped] = nil
            fromOwn[ped] = nil
        end
    end
end

-- Out of somebody else's car with its own standing near: home is the deed,
-- whatever the tag was called. "Leave my car and get back to yours" came as
-- [exit_vehicle] every time in live traces, and a driver left on the
-- pavement wandered off saying it was walking to its car.
-- Only THIS exit matters: a driver that earlier got out of its own car on
-- request, then rode along in the player's, still goes home when sent out of
-- that one (the dismissal from the first exit is not a reason to stay on foot).
local function goesHome(ped)
    if fromOwn[ped] or not HumalikeNpcDriving.OwnVehicleInReach(ped) then return false end
    NpcActions.enter_own_vehicle(ped, ActionParams[ped] or {})
    return ActionControlledPeds[ped] == 'enter_own_vehicle'
end

local function finish(ped)
    deadlines[ped] = nil
    local home = goesHome(ped)
    fromOwn[ped] = nil
    if not home then ReleaseActionControl(ped) end
end

NpcActions['exit_vehicle'] = function(ped, _params)
    forgetStaleDeadlines()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        deadlines[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    fromOwn[ped] = nil
    if NpcActionDrivesOwnVehicle(ped) then
        HumalikeNpcDriving.Dismiss(ped) -- told to get out of its own car: it stays parked
        fromOwn[ped] = true
    end
    MarkActionControl(ped, 'exit_vehicle')
    deadlines[ped] = GetGameTimer() + timeoutMs()
    TaskLeaveVehicle(ped, vehicle, 0)
end

NpcActionSustain['exit_vehicle'] = function(ped)
    forgetStaleDeadlines()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        finish(ped)
        return
    end
    deadlines[ped] = deadlines[ped] or GetGameTimer() + timeoutMs()
    if GetGameTimer() >= deadlines[ped] then
        deadlines[ped] = nil
        fromOwn[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    if GetScriptTaskStatus(ped, GetHashKey('SCRIPT_TASK_LEAVE_VEHICLE')) <= 1 then return end
    TaskLeaveVehicle(ped, vehicle, 0)
end
