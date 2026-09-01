NpcActions = NpcActions or {}

NpcActions['release_movement'] = function(ped, params)
    if NpcActionPedInVehicle(ped) and BeginStopFollowing then
        BeginStopFollowing(ped)
        return
    end
    if NpcActions['walk_away'] then
        NpcActions['walk_away'](ped, params or {})
        return
    end
    ReleaseActionControl(ped)
    ClearPedTasks(ped)
    TaskWanderStandard(ped, 10.0, 10)
end
