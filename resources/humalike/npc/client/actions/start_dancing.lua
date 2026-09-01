
NpcActions = NpcActions or {}

NpcActions['start_dancing'] = function(ped, _params)
    if NpcActionPedInVehicle(ped) then return end
    MarkActionControl(ped, 'start_dancing')
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_PARTYING', 0, true)
end

NpcActionSustain['start_dancing'] = function(ped)
    if NpcActionPedInVehicle(ped) then return end
    if IsPedActiveInScenario(ped) then return end
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_PARTYING', 0, true)
end
