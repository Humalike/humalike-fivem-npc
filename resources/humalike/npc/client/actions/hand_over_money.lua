
NpcActions = NpcActions or {}

local ANIM_DICT = 'mp_common'
local ANIM_CLIP = 'givetake1_a'

NpcActions['hand_over_money'] = function(ped, _params)
    local borrowed = not IsActionControlled(ped)
    if borrowed then MarkActionControl(ped, 'hand_over_money') end
    RequestAnimDict(ANIM_DICT)
    local attempts = 0
    while not HasAnimDictLoaded(ANIM_DICT) and attempts < 100 do
        Wait(50)
        attempts = attempts + 1
    end
    if not HasAnimDictLoaded(ANIM_DICT) then
        print('[humalike-npc] hand_over_money: anim dict failed to load')
        if borrowed then ReleaseActionControl(ped) end
        return
    end
    TaskPlayAnim(ped, ANIM_DICT, ANIM_CLIP, 8.0, -8.0, Config.Robbery.HandoverAnimMs, 49, 0,
        false, false, false)
    if borrowed then
        SetTimeout(Config.Robbery.HandoverAnimMs, function()
            if ActionControlledPeds[ped] == 'hand_over_money' then ReleaseActionControl(ped) end
        end)
    end
end
