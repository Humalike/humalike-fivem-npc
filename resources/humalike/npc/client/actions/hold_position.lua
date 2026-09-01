NpcActions = NpcActions or {}

NpcActions['hold_position'] = function(ped, _params)
    if BeginStopFollowing then
        BeginStopFollowing(ped)
    else
        ReleaseActionControl(ped)
        if not NpcActionPedInVehicle(ped) then ClearPedTasks(ped) end
    end
    if NpcActionPedInVehicle(ped) then return end
    TaskStandStill(ped, Config.AmbientControl.StandTaskDurationMs)
end
