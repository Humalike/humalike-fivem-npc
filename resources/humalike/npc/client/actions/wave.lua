
NpcActions = NpcActions or {}

local ANIM_DICT = 'gestures@m@standing@casual'
local ANIM_CLIP = 'gesture_hello'

NpcActions['wave'] = function(ped, _params)
    local borrowed = not IsActionControlled(ped)
    if borrowed then MarkActionControl(ped, 'wave') end
    RequestAnimDict(ANIM_DICT)
    local attempts = 0
    while not HasAnimDictLoaded(ANIM_DICT) and attempts < 100 do
        Wait(50)
        attempts = attempts + 1
    end
    if not HasAnimDictLoaded(ANIM_DICT) then
        print('[humalike-npc] wave: anim dict failed to load')
        if borrowed then ReleaseActionControl(ped) end
        return
    end
    TaskPlayAnim(ped, ANIM_DICT, ANIM_CLIP, 8.0, -8.0, -1, 0, 0, false, false, false)
    if borrowed then
        SetTimeout(Config.Wave.DurationMs, function()
            if ActionControlledPeds[ped] == 'wave' then ReleaseActionControl(ped) end
        end)
    end
end
