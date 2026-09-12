
local downed = {} -- npcId -> { entity, state, entityId, networkId }
local lingering = {}
local lingerGeneration = 0
local TreatmentInProgress = false
local staticInteractionIds = {}
local treatmentRoles = { medic = false, police = false }
local rolesRequestedAt = nil

RegisterNetEvent('humalike:npc:treatmentRoles')
AddEventHandler('humalike:npc:treatmentRoles', function(roles)
    if type(roles) ~= 'table' then return end
    local medic, police = roles.medic == true, roles.police == true
    local changed = medic ~= treatmentRoles.medic or police ~= treatmentRoles.police
    treatmentRoles.medic = medic
    treatmentRoles.police = police
    if changed then TriggerEvent('humalike:npc:treatmentAccessChanged') end
end)

local function requestTreatmentRoles()
    local now = GetGameTimer()
    local refresh = tonumber((Config.Wounded or {}).RolesRefreshMs) or 20000
    if rolesRequestedAt and now - rolesRequestedAt < refresh then return end
    rolesRequestedAt = now
    TriggerServerEvent('humalike:npc:requestTreatmentRoles')
end
local DOWNED_DICT = 'dead'
local DOWNED_CLIP = 'dead_a'
local FALLBACK_DICT = 'mp_sleep'
local FALLBACK_CLIP = 'bind_pose_180'
CreateThread(function()
    RequestAnimDict(DOWNED_DICT)
    RequestAnimDict(FALLBACK_DICT)
end)

local function pedFor(npcId)
    local ped = LoadedPeds and LoadedPeds[npcId] or nil
    if ped and DoesEntityExist(ped) then return ped end
    local entry = AmbientPeds and AmbientPeds[npcId] or nil
    if entry and DoesEntityExist(entry) then return entry end
    return nil
end

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(dict)
end
local function playDownedPose(ped)
    ClearPedTasksImmediately(ped)
    if loadDict(DOWNED_DICT) then
        TaskPlayAnim(ped, DOWNED_DICT, DOWNED_CLIP, 8.0, 0.0, -1, 1, 0.0, false, false, false)
        return true
    end
    if loadDict(FALLBACK_DICT) then
        TaskPlayAnim(ped, FALLBACK_DICT, FALLBACK_CLIP, 8.0, 0.0, -1, 1, 0.0, false, false, false)
        return true
    end
    SetPedCanRagdoll(ped, true)
    SetPedToRagdoll(ped, 60000, 60000, 0, false, false, false)
    return false
end

local function isHoldingPose(ped)
    return IsEntityPlayingAnim(ped, DOWNED_DICT, DOWNED_CLIP, 3)
        or IsEntityPlayingAnim(ped, FALLBACK_DICT, FALLBACK_CLIP, 3)
        or IsPedRagdoll(ped)
end
local LINGER_STAND_TASK_MS = 4000

local POSE_WATCH_TICK_MS = 100
local POSE_MISSES_BEFORE_REAPPLY = 2
local POSE_REAPPLY_COOLDOWN_MS = 400
local function holdDownedFlags(ped)
    -- Owner-local flags must be reapplied after OneSync ownership migration.
    if NetworkHasControlOfEntity(ped) then SetEntityAsMissionEntity(ped, true, true) end
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedRagdollOnCollision(ped, false)
    SetPedDiesInWater(ped, false)
    SetPedKeepTask(ped, false)
    HumalikeNpcReactions.Own(ped)
    FreezeEntityPosition(ped, true)
end

local function applyDowned(ped)
    if ReleaseActionControl then ReleaseActionControl(ped) end
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then
        ResurrectPed(ped)
        ClearPedBloodDamage(ped)
    end
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    holdDownedFlags(ped)
    playDownedPose(ped)
end
local function releaseBody(ped)
    if not DoesEntityExist(ped) or not NetworkHasControlOfEntity(ped) then return end
    SetPedAsNoLongerNeeded(ped)
end

local function clearDowned(ped)
    if not DoesEntityExist(ped) then return end
    releaseBody(ped)
    FreezeEntityPosition(ped, false)
    HumalikeNpcReactions.Release(ped)
    SetEntityInvincible(ped, false)
    SetEntityCanBeDamaged(ped, true)
    SetPedSuffersCriticalHits(ped, true)
    SetPedDiesInWater(ped, true)
    SetPedCanRagdoll(ped, true)
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
end
local function holdStanding(npcId, ped)
    if downed[npcId] then return end
    if not NetworkHasControlOfEntity(ped) then return end
    HumalikeNpcReactions.Own(ped)
    TaskStandStill(ped, LINGER_STAND_TASK_MS)
end
local function releaseFromHold(npcId, ped)
    if downed[npcId] or not DoesEntityExist(ped) then return end
    if not NetworkHasControlOfEntity(ped) then return end
    HumalikeNpcReactions.Release(ped)
    -- A population body gets its planned stand/scenario back; anyone else wanders.
    if HumalikeNpcPopulationClient and HumalikeNpcPopulationClient.Reapply(ped) then return end
    ClearPedTasks(ped)
    TaskWanderStandard(ped, 10.0, 10)
end

local function lingerAfterRevive(npcId, ped, durationMs, radius)
    lingerGeneration = lingerGeneration + 1
    local generation = lingerGeneration
    -- Generations stop superseded hold threads from tasking the same body.
    lingering[npcId] = generation
    holdStanding(npcId, ped)
    CreateThread(function()
        local clearSince = nil
        while lingering[npcId] == generation and DoesEntityExist(ped) do
            Wait(1000)
            local coords = GetEntityCoords(ped)
            local someoneNear = false
            for _, playerId in ipairs(GetActivePlayers()) do
                local other = GetPlayerPed(playerId)
                if DoesEntityExist(other)
                    and #(GetEntityCoords(other) - coords) <= radius then
                    someoneNear = true
                    break
                end
            end
            if someoneNear then
                clearSince = nil
                holdStanding(npcId, ped)
            else
                clearSince = clearSince or GetGameTimer()
                if GetGameTimer() - clearSince >= durationMs then break end
            end
        end
        if lingering[npcId] ~= generation then return end
        lingering[npcId] = nil
        releaseFromHold(npcId, ped)
    end)
end

RegisterNetEvent('humalike:npc:npcDownedState')
AddEventHandler('humalike:npc:npcDownedState', function(npcId, payload)
    if type(npcId) ~= 'string' or type(payload) ~= 'table' then return end
    local ped = pedFor(npcId)
    local state = payload.state

    if state == 'wounded' or state == 'deceased' then
        downed[npcId] = {
            entity = ped, state = state, posedAt = GetGameTimer(), poseMisses = 0,
            entityId = tonumber(payload.entity_id),
            networkId = tonumber(payload.network_id),
        }
        requestTreatmentRoles()
        TriggerEvent('humalike:npc:npcDownedChanged', npcId)
        lingering[npcId] = nil
        if ped then applyDowned(ped) end
    elseif state == 'revived' then
        downed[npcId] = nil
        TriggerEvent('humalike:npc:npcDownedChanged', npcId)
        if not ped then return end
        clearDowned(ped)
        lingerAfterRevive(npcId, ped,
            tonumber(payload.linger_ms) or 30000,
            tonumber(payload.linger_radius) or 20.0)
    elseif state == 'gone' then
        downed[npcId] = nil
        lingering[npcId] = nil
        if ped then
            SetEntityInvincible(ped, false)
            SetPedCanRagdoll(ped, true)
            FreezeEntityPosition(ped, false)
            if NetworkHasControlOfEntity(ped) then
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
            else
                SetEntityHealth(ped, 0)
            end
            releaseBody(ped)
        end
        TriggerEvent('humalike:npc:npcBodyReleased', npcId)
    end
end)
function HumalikeDownedState(npcId)
    local entry = downed[npcId]
    return entry and entry.state or nil
end
CreateThread(function()
    while true do
        Wait(POSE_WATCH_TICK_MS)
        for npcId, entry in pairs(downed) do
            if not entry.entity or not DoesEntityExist(entry.entity) then
                local lease = AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
                local leaseEntity = lease and tonumber(lease.entity_id) or nil
                if entry.entityId and leaseEntity == entry.entityId then
                    local found = pedFor(npcId)
                    if found then
                        entry.entity = found
                        entry.posedAt = GetGameTimer()
                        entry.poseMisses = 0
                        entry.goneSince = nil
                        applyDowned(found)
                    end
                elseif entry.entityId and leaseEntity and leaseEntity ~= entry.entityId then
                    downed[npcId] = nil
                    lingering[npcId] = nil
                    TriggerEvent('humalike:npc:npcBodyReleased', npcId)
                elseif entry.networkId and NetworkDoesEntityExistWithNetworkId(entry.networkId) then
                    local found = NetworkGetEntityFromNetworkId(entry.networkId)
                    if found and found > 0 and DoesEntityExist(found) then
                        entry.entity = found
                        entry.posedAt = GetGameTimer()
                        entry.poseMisses = 0
                        entry.goneSince = nil
                        applyDowned(found)
                    end
                elseif not entry.entityId then
                    if entry.state == 'wounded' then
                        local found = pedFor(npcId)
                        if found then
                            entry.entity = found
                            entry.posedAt = GetGameTimer()
                            entry.poseMisses = 0
                            entry.goneSince = nil
                            applyDowned(found)
                        end
                    else
                        entry.goneSince = entry.goneSince or GetGameTimer()
                        if GetGameTimer() - entry.goneSince >= 3000 then
                            downed[npcId] = nil
                            lingering[npcId] = nil
                            TriggerEvent('humalike:npc:npcBodyReleased', npcId)
                        end
                    end
                end
            else
                entry.goneSince = nil
            end
            local ped = entry.entity
            if ped and DoesEntityExist(ped) then
                if GetEntityHealth(ped) < GetEntityMaxHealth(ped) then
                    SetEntityHealth(ped, GetEntityMaxHealth(ped))
                end
                if isHoldingPose(ped) then
                    entry.poseMisses = 0
                else
                    entry.poseMisses = (entry.poseMisses or 0) + 1
                    local now = GetGameTimer()
                    if entry.poseMisses >= POSE_MISSES_BEFORE_REAPPLY
                        and now - (entry.posedAt or 0) >= POSE_REAPPLY_COOLDOWN_MS then
                        entry.poseMisses = 0
                        entry.posedAt = now
                        playDownedPose(ped)
                    end
                end
                holdDownedFlags(ped)
                local owned = NetworkHasControlOfEntity(ped)
                if owned and not entry.owned then
                    entry.poseMisses = 0
                    entry.posedAt = GetGameTimer()
                    playDownedPose(ped)
                end
                entry.owned = owned
            end
        end
    end
end)
function HumalikeTreatmentOptions(npcId)
    if (Config.Wounded or {}).Enabled == false then return {} end
    local function stateIs(want, allowed)
        return function()
            requestTreatmentRoles()
            return allowed() and HumalikeDownedState(npcId) == want
                and not TreatmentInProgress
        end
    end
    local function treat(intent, durationMs, label)
        return function()
            if TreatmentInProgress then return end
            local ped = pedFor(npcId)
            if not ped then return end
            TreatmentInProgress = true
            local completed = HumalikeInteractionProgress(durationMs, label, ped)
            TreatmentInProgress = false
            if completed then
                TriggerServerEvent('humalike:npc:finishNpcTreatment', npcId, intent)
            end
        end
    end
    local wounded = Config.Wounded or {}
    local options = {}
    local state = HumalikeDownedState(npcId)
    if state == 'wounded' and treatmentRoles.medic then
        options[#options + 1] = {
            text = wounded.ReviveLabel or 'Revive',
            icon = 'kit-medical',
            canInteract = stateIs('wounded', function()
                return treatmentRoles.medic
            end),
            onSelect = treat('revive',
                tonumber(wounded.ReviveDurationMs) or 10000,
                wounded.ReviveProgressLabel or 'Treating patient'),
        }
    end
    if state == 'deceased' and (treatmentRoles.medic or treatmentRoles.police) then
        options[#options + 1] = {
            text = wounded.MortuaryLabel or 'Send to mortuary',
            icon = 'cross',
            canInteract = stateIs('deceased', function()
                return treatmentRoles.medic or treatmentRoles.police
            end),
            onSelect = treat('mortuary',
                tonumber(wounded.MortuaryDurationMs) or 5000,
                wounded.MortuaryProgressLabel or 'Securing the body'),
        }
    end
    return options
end
CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(500) end
    TriggerServerEvent('humalike:npc:requestDownedStates')
    while true do
        requestTreatmentRoles()
        Wait(tonumber((Config.Wounded or {}).RolesRefreshMs) or 5000)
    end
end)
