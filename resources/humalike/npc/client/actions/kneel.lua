
NpcActions = NpcActions or {}

local ANIM_DICT = 'random@arrests@busted'
local ANIM_CLIP = 'idle_a'

local function playKneel(ped)
    TaskPlayAnim(ped, ANIM_DICT, ANIM_CLIP, 8.0, -8.0, -1, 1, 0, false, false, false)
end

NpcActions['kneel'] = function(ped, _params)
    if NpcActionPedInVehicle(ped) then return end
    MarkActionControl(ped, 'kneel')
    RequestAnimDict(ANIM_DICT)
    local attempts = 0
    while not HasAnimDictLoaded(ANIM_DICT) and attempts < 100 do
        Wait(50)
        attempts = attempts + 1
    end
    if ActionControlledPeds[ped] ~= 'kneel' then
        return
    end
    if not HasAnimDictLoaded(ANIM_DICT) then
        print('[humalike-npc] kneel: anim dict failed to load')
        ReleaseActionControl(ped)
        return
    end
    playKneel(ped)
end
NpcActionSustain['kneel'] = function(ped)
    if NpcActionPedInVehicle(ped) then return end
    if IsEntityPlayingAnim(ped, ANIM_DICT, ANIM_CLIP, 3) then return end
    if not HasAnimDictLoaded(ANIM_DICT) then
        RequestAnimDict(ANIM_DICT)
        return
    end
    playKneel(ped)
end
