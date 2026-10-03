
local pendingDeathChecks = {}

AddEventHandler('entityDamaged', function(victim, culprit, weapon, baseDamage)
    if culprit ~= PlayerPedId() then return end
    local npcId = Entity(victim).state.humalike_npc_id
    if not npcId then return end
    if HumalikeNpcShove then HumalikeNpcShove.NoteDamage(victim, GetGameTimer()) end
    if LoadedPeds and LoadedPeds[npcId] == victim then
        SetEntityHealth(victim, GetEntityMaxHealth(victim))
    end

    local ambientEntry = AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
    local entityId = ambientEntry and ambientEntry.entity_id or nil
    -- Read the bone immediately on the owning client; the server classifies it.
    local hasBone, bone = GetPedLastDamageBone(victim)
    TriggerServerEvent('humalike:npc:npcDamaged', npcId, entityId or -1,
        hasBone and bone or 0, weapon, baseDamage or 0)
    if HumalikeDownedState and HumalikeDownedState(npcId) then
        SetEntityHealth(victim, GetEntityMaxHealth(victim))
        return
    end

    HumalikeDebug('npc %s attacked, weapon=0x%08X damage=%s', npcId, weapon,
        tostring(baseDamage))
    TriggerServerEvent('humalike:npc:npcAttacked', npcId, entityId, weapon,
        baseDamage, HumalikeWeaponName and HumalikeWeaponName(weapon) or nil)
    if entityId and not pendingDeathChecks[victim] then
        pendingDeathChecks[victim] = true
        SetTimeout(150, function()
            pendingDeathChecks[victim] = nil
            if DoesEntityExist(victim)
                and Entity(victim).state.humalike_npc_id == npcId
                and (IsEntityDead(victim) or IsPedDeadOrDying(victim, true)) then
                TriggerServerEvent('humalike:npc:npcDied', npcId, entityId)
            end
        end)
    end
end)

CreateThread(function()
    while true do
        Wait(next(LoadedPeds or {}) and 500 or 1500)
        for npcId, ped in pairs(LoadedPeds or {}) do
            if DoesEntityExist(ped) and not IsEntityDead(ped)
                and not (HumalikeDownedState and HumalikeDownedState(npcId)) then
                SetEntityHealth(ped, GetEntityMaxHealth(ped))
            end
        end
    end
end)

-- The player's gun. Every 100 ms (50 ms while aiming at somebody) a pulse job
-- looks at the hand and the aim; only while a gun is out does a frame job
-- watch for shots, one native a frame.
local gunPed, armed = 0, false
local burstOpen, lastShotAt = false, -1000
local aimingAt = nil

local function watchShots()
    if not armed and not burstOpen then return false end
    if IsPedShooting(gunPed) then
        lastShotAt = GetGameTimer()
        if not burstOpen then
            burstOpen = true
            TriggerServerEvent('humalike:npc:gunshotFired')
        end
    elseif burstOpen and GetGameTimer() - lastShotAt >= 500 then
        burstOpen = false
    end
    return true
end

HumalikePulse.EveryFrame('gunshots', watchShots)

HumalikePulse.Every('gun', 100, function()
    local wasArmed = armed
    gunPed = HumalikePulse.Ped()
    armed = IsPedArmed(gunPed, 6)
    if armed then
        -- The frame the gun is first seen counts too: the frame job starts on the next one.
        if not wasArmed then watchShots() end
        HumalikePulse.Frames()
    end
    local playerId = PlayerId()
    local npcId = nil
    if IsPlayerFreeAiming(playerId) then
        local found, entity = GetEntityPlayerIsFreeAimingAt(playerId)
        npcId = found and IsEntityAPed(entity)
            and Entity(entity).state.humalike_npc_id or nil
    end
    if npcId ~= aimingAt then
        aimingAt = npcId
        local entry = npcId and AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
        TriggerServerEvent('humalike:npc:aimingCandidateChanged', npcId,
            entry and entry.entity_id or nil)
    end
    return aimingAt and 50 or 100
end)
