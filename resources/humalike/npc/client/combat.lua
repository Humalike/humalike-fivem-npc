
local pendingDeathChecks = {}

-- Only static roster NPCs are unkillable; dynamic roster NPCs keep GTA health
-- and go through the wounded/deceased flow like population bodies.
local function healsToFull(npcId)
    local entry = KnownNpcs and KnownNpcs[npcId] or nil
    return entry ~= nil and entry.type == 'static'
end

AddEventHandler('entityDamaged', function(victim, culprit, weapon, baseDamage)
    if culprit ~= PlayerPedId() then return end
    local npcId = Entity(victim).state.humalike_npc_id
    if not npcId then return end
    if HumalikeNpcShove then HumalikeNpcShove.NoteDamage(victim, GetGameTimer()) end
    local rosterPed = LoadedPeds and LoadedPeds[npcId] == victim
    if rosterPed and healsToFull(npcId) then
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
    -- Ambient/population bodies report with their entity id; dynamic roster
    -- peds report without one and the server resolves its own entity.
    if (entityId or (rosterPed and not healsToFull(npcId))) and not pendingDeathChecks[victim] then
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
            if DoesEntityExist(ped) and not IsEntityDead(ped) and healsToFull(npcId)
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
        Wait(0)
        local now = GetGameTimer()
        if IsPedShooting(PlayerPedId()) then
            lastShotAt = now
            if not burstOpen then
                burstOpen = true
                TriggerServerEvent('humalike:npc:gunshotFired')
            end
        elseif burstOpen and now - lastShotAt >= 500 then
            burstOpen = false
        end
    end
end)

CreateThread(function()
    local aimingAt
    while true do
        Wait(50)
        local found, entity = GetEntityPlayerIsFreeAimingAt(PlayerId())
        local npcId = found and IsEntityAPed(entity)
            and Entity(entity).state.humalike_npc_id or nil
        if npcId ~= aimingAt then
            aimingAt = npcId
            local entry = npcId and AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
            TriggerServerEvent('humalike:npc:aimingCandidateChanged', npcId,
                entry and entry.entity_id or nil)
        end
    end
end)
