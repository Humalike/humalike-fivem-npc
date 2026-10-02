
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

CreateThread(function()
    local burstOpen = false
    local lastShotAt = -1000
    while true do
        local ped = PlayerPedId()
        if burstOpen or IsPedArmed(ped, 6) then
            local now = GetGameTimer()
            if IsPedShooting(ped) then
                lastShotAt = now
                if not burstOpen then
                    burstOpen = true
                    TriggerServerEvent('humalike:npc:gunshotFired')
                end
            elseif burstOpen and now - lastShotAt >= 500 then
                burstOpen = false
            end
            Wait(0)
        else
            Wait(100)
        end
    end
end)

-- The aim target is read only while the player aims; otherwise one native
-- every 100 ms says there is nothing to read.
CreateThread(function()
    local aimingAt
    while true do
        Wait(aimingAt and 50 or 100)
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
    end
end)
