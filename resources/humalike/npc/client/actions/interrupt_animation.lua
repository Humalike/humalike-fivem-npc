
NpcActions = NpcActions or {}

NpcActions['interrupt_animation'] = function(ped, _params)
    ReleaseActionControl(ped)
    if NpcActionPedInVehicle(ped) then return end
    ClearPedTasksImmediately(ped)
end
