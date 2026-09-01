
NpcActions = NpcActions or {}

NpcActions['hands_up'] = function(ped, _params)
    if NpcActionPedInVehicle(ped) then return end
    MarkActionControl(ped, 'hands_up')
    TaskHandsUp(ped, -1, 0, -1, false)
end
NpcActionSustain['hands_up'] = function(ped)
    if NpcActionPedInVehicle(ped) then return end
    if GetScriptTaskStatus(ped, GetHashKey('SCRIPT_TASK_HANDS_UP')) <= 1 then return end
    TaskHandsUp(ped, -1, 0, -1, false)
end
