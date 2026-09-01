
local speakingNpcs = {}

local function setMouthAnimation(ped, active)
    if active then
        PlayFacialAnim(ped, 'mic_chatter', 'mp_facial')
    else
        local dictionary = IsPedMale(ped) and 'facials@gen_male@variations@normal'
            or 'facials@gen_female@variations@normal'
        PlayFacialAnim(ped, 'mood_normal_1', dictionary)
    end
end

local function animate(npcId, active)
    local ped = ResolveNpcPed(npcId)
    if not ped or not DoesEntityExist(ped) or IsEntityDead(ped) then return end
    setMouthAnimation(ped, active)
end

AddEventHandler('humalike-voice:npcSpeaking', function(npcId, active)
    if type(npcId) ~= 'string' then return end
    if active == true then
        speakingNpcs[npcId] = true
        animate(npcId, true)
    elseif speakingNpcs[npcId] then
        speakingNpcs[npcId] = nil
        animate(npcId, false)
    end
end)

CreateThread(function()
    while true do
        local hasSpeakers = false
        for npcId in pairs(speakingNpcs) do
            hasSpeakers = true
            animate(npcId, true)
        end
        Wait(hasSpeakers and 500 or 1500)
    end
end)

AddEventHandler('humalike:npc:npcRemoved', function(npcId)
    speakingNpcs[npcId] = nil
end)

AddEventHandler('humalike:npc:ambientPedRemoved', function(npcId)
    speakingNpcs[npcId] = nil
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for npcId in pairs(speakingNpcs) do animate(npcId, false) end
    speakingNpcs = {}
end)
