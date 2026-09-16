
NpcActions = NpcActions or {}

local deadlines = {}

local function timeoutMs()
    return Config.Follow.VehicleTaskTimeoutMs or 10000
end

local function forgetStaleDeadlines()
    for ped in pairs(deadlines) do
        if ActionControlledPeds[ped] ~= 'exit_vehicle' then deadlines[ped] = nil end
    end
end

NpcActions['exit_vehicle'] = function(ped, _params)
    forgetStaleDeadlines()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        deadlines[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    if NpcActionDrivesOwnVehicle and NpcActionDrivesOwnVehicle(ped) then
        HumalikeNpcDriving.Dismiss(ped) -- told to get out: the car stays parked
    end
    MarkActionControl(ped, 'exit_vehicle')
    deadlines[ped] = GetGameTimer() + timeoutMs()
    TaskLeaveVehicle(ped, vehicle, 0)
end

NpcActionSustain['exit_vehicle'] = function(ped)
    forgetStaleDeadlines()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then
        deadlines[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    deadlines[ped] = deadlines[ped] or GetGameTimer() + timeoutMs()
    if GetGameTimer() >= deadlines[ped] then
        deadlines[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    if GetScriptTaskStatus(ped, GetHashKey('SCRIPT_TASK_LEAVE_VEHICLE')) <= 1 then return end
    TaskLeaveVehicle(ped, vehicle, 0)
end
