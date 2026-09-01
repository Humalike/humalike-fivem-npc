
NpcActions = NpcActions or {}
local BF_ALWAYS_FIGHT = 46

NpcActions['punch'] = function(ped, params)
    if NpcActionPedInVehicle(ped) then return end
    local target = ActionTargetPed(ped, params, Config.Punch.MaxDistance)
    if not target then
        print('[humalike-npc] punch: nobody within reach')
        return
    end
    SetCurrentPedWeapon(ped, GetHashKey('WEAPON_UNARMED'), true)
    SetPedCombatAttributes(ped, BF_ALWAYS_FIGHT, true)
    MarkActionControl(ped, 'punch')
    TaskCombatPed(ped, target, 0, 16)
    SetTimeout(Config.Punch.DurationMs, function()
        local ownsPunch = ActionControlledPeds[ped] == 'punch'
        if ownsPunch then ReleaseActionControl(ped) end
        if DoesEntityExist(ped) then
            SetPedCombatAttributes(ped, BF_ALWAYS_FIGHT, false)
            if ownsPunch and not NpcActionPedInVehicle(ped) then ClearPedTasks(ped) end
        end
    end)
end
