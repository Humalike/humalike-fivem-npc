NpcActions = NpcActions or {}

NpcActions['hold_position'] = function(ped, _params)
    if NpcActionDrivesOwnVehicle(ped) then
        -- A driver told to stop brakes; the hold the server installs keeps it braked.
        ReleaseActionControl(ped)
        HumalikeNpcDriving.Brake(ped, true)
        return
    end
    if BeginStopFollowing then
        BeginStopFollowing(ped)
    else
        ReleaseActionControl(ped)
        if not NpcActionPedInVehicle(ped) then ClearPedTasks(ped) end
    end
    if NpcActionPedInVehicle(ped) then return end
    TaskStandStill(ped, Config.AmbientControl.StandTaskDurationMs)
end
