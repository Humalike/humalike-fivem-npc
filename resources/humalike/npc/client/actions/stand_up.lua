
NpcActions = NpcActions or {}

NpcActions['stand_up'] = function(ped, _params)
    ReleaseActionControl(ped)
    if NpcActionPedInVehicle(ped) then return end
    ClearPedTasks(ped)
end
