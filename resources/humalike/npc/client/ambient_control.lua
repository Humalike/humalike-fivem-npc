
local controls = {}
local interactionIds = {}
local ambientByControlKey = {}
local initializedHoldByPed = {}
local reviveInProgress = false

local function controlKey(entry)
    return tostring(entry.entity_id)
end

local function interactionId(npcId)
    return ('humalike-ambient-control:%s'):format(npcId)
end

local function adapter()
    return HumalikeInteractionAdapter and HumalikeInteractionAdapter() or nil
end

local function silencePed(ped, toggle)
    if not ped or not DoesEntityExist(ped) then return end
    StopPedSpeaking(ped, toggle)
    DisablePedPainAudio(ped, toggle)
end

local function setHeldReactionsBlocked(ped, blocked)
    if not ped or not DoesEntityExist(ped) or not NetworkHasControlOfEntity(ped) then return end
    if blocked then
        HumalikeNpcReactions.Own(ped, true)
    else
        HumalikeNpcReactions.Release(ped, true)
    end
end

-- Returns true while a turn is in progress, so no stand-still is stamped over it.
local function faceController(ped, control)
    local player = GetPlayerFromServerId(control.controller_source or -1)
    local target = player ~= -1 and GetPlayerPed(player) or 0
    if target <= 0 or not DoesEntityExist(target) then return false end
    local duration = Config.AmbientControl.StandTaskDurationMs
    TaskLookAtEntity(ped, target, duration, 2048, 3)
    local toTarget = GetEntityCoords(target) - GetEntityCoords(ped)
    local desired = GetHeadingFromVector_2d(toTarget.x, toTarget.y)
    local delta = (desired - GetEntityHeading(ped) + 540.0) % 360.0 - 180.0
    if math.abs(delta) <= Config.AmbientControl.FaceToleranceDeg then return false end
    TaskTurnPedToFaceEntity(ped, target, duration)
    return true
end

function HumalikeAmbientControlHeldPed(ped)
    local npcId = DoesEntityExist(ped) and Entity(ped).state.humalike_npc_id or nil
    local entry = npcId and AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
    local control = entry and controls[controlKey(entry)] or nil
    return control ~= nil and control.mode == 'held'
end

local function removeInteraction(npcId)
    local id = interactionIds[npcId]
    local currentAdapter = adapter()
    if id and currentAdapter then HumalikeInteractionRemove(currentAdapter, id) end
    interactionIds[npcId] = nil
end
local function isDowned(npcId)
    return HumalikeDownedState ~= nil and HumalikeDownedState(npcId) ~= nil
end

local function addInteraction(npcId)
    if interactionIds[npcId] then return end
    local ped = AmbientPeds and AmbientPeds[npcId] or nil
    local entry = AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
    local currentAdapter = adapter()
    if not ped or not DoesEntityExist(ped) or not entry or not currentAdapter then return end
    local id = interactionId(npcId)
    -- Target resources can outlive this resource; replace stale registrations.
    HumalikeInteractionRemove(currentAdapter, id)

    if isDowned(npcId) then
        local treatment = HumalikeTreatmentOptions and HumalikeTreatmentOptions(npcId) or {}
        HumalikeDebug('body wheel npc %s: state=%s options=%d',
            npcId, tostring(HumalikeDownedState(npcId)), #treatment)
        if #treatment == 0 then return end
        if HumalikeInteractionAdd(currentAdapter, id, ped, treatment) then
            interactionIds[npcId] = id
        end
        return
    end

    local options = {}
    if (Config.Wounded or {}).Enabled == false then
        options[#options + 1] = {
            text = 'Pomóż wstać',
            icon = 'kit-medical',
            canInteract = function(entity)
                return not reviveInProgress
                    and (IsEntityDead(entity) or IsPedDeadOrDying(entity, true))
            end,
            onSelect = function()
                if reviveInProgress then return end
                local currentEntry = AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
                if not currentEntry then return end
                TriggerServerEvent('humalike:npc:beginAmbientRevive', currentEntry.entity_id,
                    npcId, currentEntry.lease_token)
            end,
        }
    end
    if #options == 0 then return end
    if HumalikeInteractionAdd(currentAdapter, id, ped, options) then
        interactionIds[npcId] = id
    end
end
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for npcId in pairs(interactionIds) do removeInteraction(npcId) end
end)
local function rebuildInteraction(npcId)
    removeInteraction(npcId)
    addInteraction(npcId)
end

AddEventHandler('humalike:npc:npcDownedChanged', function(npcId)
    rebuildInteraction(npcId)
end)
AddEventHandler('humalike:npc:treatmentAccessChanged', function()
    for npcId in pairs(AmbientPeds or {}) do
        if isDowned(npcId) then rebuildInteraction(npcId) end
    end
end)

local function refreshAllInteractions()
    for npcId in pairs(AmbientPeds or {}) do addInteraction(npcId) end
end

local function resumePedForKey(key)
    for npcId, entry in pairs(AmbientNpcEntries or {}) do
        if controlKey(entry) == key then
            local ped = AmbientPeds[npcId]
            if ped then initializedHoldByPed[ped] = nil end
            if ped and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped)
                and not IsActionControlled(ped) and not isDowned(npcId) then
                setHeldReactionsBlocked(ped, false)
                if Entity(ped).state.humalike_npc_kind == 'population'
                    and HumalikeNpcPopulationClient then
                    HumalikeNpcPopulationClient.Reapply(ped)
                else
                    ClearPedTasks(ped)
                    TaskWanderStandard(ped, 10.0, 10)
                end
            end
        end
    end
end

RegisterNetEvent('humalike:npc:ambientControlChanged')
AddEventHandler('humalike:npc:ambientControlChanged', function(key, control)
    local previous = controls[key]
    controls[key] = control
    if previous and not control then resumePedForKey(key) end
end)

RegisterNetEvent('humalike:npc:ambientControlSnapshot')
AddEventHandler('humalike:npc:ambientControlSnapshot', function(snapshot)
    local previous = controls
    controls = type(snapshot) == 'table' and snapshot or {}
    for key in pairs(previous) do
        if not controls[key] then resumePedForKey(key) end
    end
end)

AddEventHandler('humalike:npc:ambientPedAssigned', function(npcId, ped, entry)
    entry = entry or (AmbientNpcEntries and AmbientNpcEntries[npcId])
    if entry then ambientByControlKey[controlKey(entry)] = npcId end
    silencePed(ped, true)
    addInteraction(npcId)
end)
AddEventHandler('humalike:npc:npcBodyReleased', function(npcId)
    removeInteraction(npcId)
end)

AddEventHandler('humalike:npc:ambientPedRemoved', function(npcId, ped, entry)
    removeInteraction(npcId)
    silencePed(ped, false)
    if ped then initializedHoldByPed[ped] = nil end
    if entry then
        ambientByControlKey[controlKey(entry)] = nil
        local control = controls[controlKey(entry)]
        if control and DoesEntityExist(ped) and NetworkHasControlOfEntity(ped)
            and not IsActionControlled(ped) and not isDowned(npcId) then
            setHeldReactionsBlocked(ped, false)
            ClearPedTasks(ped)
            TaskWanderStandard(ped, 10.0, 10)
        end
    end
end)

local function loadAnimDict(name)
    if HasAnimDictLoaded(name) then return true end
    RequestAnimDict(name)
    local deadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded(name) and GetGameTimer() < deadline do Wait(0) end
    return HasAnimDictLoaded(name)
end

RegisterNetEvent('humalike:npc:ambientReviveStarted')
AddEventHandler('humalike:npc:ambientReviveStarted', function(session)
    if reviveInProgress or type(session) ~= 'table' then return end
    local ped = 0
    if NetworkDoesEntityExistWithNetworkId(session.network_id) then
        ped = NetworkGetEntityFromNetworkId(session.network_id)
    end
    if not ped or ped <= 0 or not DoesEntityExist(ped) then
        TriggerServerEvent('humalike:npc:cancelAmbientRevive', session.key)
        return
    end

    reviveInProgress = true
    local playerPed = PlayerPedId()
    local animDict = 'missah_2_ext_altleadinout'
    if loadAnimDict(animDict) then
        TaskPlayAnim(playerPed, animDict, 'hack_loop', 8.0, 8.0, -1, 1, 0.0, false, false, false)
    end
    local deadline = GetGameTimer() + (session.duration_ms or Config.AmbientRevive.DurationMs)
    local completed = true
    while GetGameTimer() < deadline do
        Wait(100)
        if not DoesEntityExist(ped) or not (IsEntityDead(ped) or IsPedDeadOrDying(ped, true))
            or #(GetEntityCoords(playerPed) - GetEntityCoords(ped))
                > Config.AmbientRevive.InteractionDistance
            or IsEntityDead(playerPed) or IsControlJustReleased(0, 73) then
            completed = false
            break
        end
    end
    StopAnimTask(playerPed, animDict, 'hack_loop', 2.0)
    RemoveAnimDict(animDict)
    reviveInProgress = false
    TriggerServerEvent(completed and 'humalike:npc:completeAmbientRevive'
        or 'humalike:npc:cancelAmbientRevive', session.key)
end)

RegisterNetEvent('humalike:npc:reviveAmbientPed')
AddEventHandler('humalike:npc:reviveAmbientPed', function(entityId, networkId, npcId, leaseToken)
    local entry = AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
    local ped = AmbientPeds and AmbientPeds[npcId] or nil
    if not entry or entry.entity_id ~= entityId or entry.network_id ~= networkId
        or entry.lease_token ~= leaseToken
        or not ped or not DoesEntityExist(ped) or not NetworkHasControlOfEntity(ped) then return end

    ResurrectPed(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
    TaskWanderStandard(ped, 10.0, 10)
end)

AddEventHandler('humalike:interaction:providerChanged', function(
    _providerName, previousName, previousAdapter)
    previousAdapter = previousAdapter or (HumalikeInteractionAdapterByName
        and HumalikeInteractionAdapterByName(previousName) or nil)
    if previousAdapter then
        for _, id in pairs(interactionIds) do
            HumalikeInteractionRemove(previousAdapter, id)
        end
    end
    interactionIds = {}
    refreshAllInteractions()
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if HumalikeIsInteractionResource and HumalikeIsInteractionResource(resourceName) then
        refreshAllInteractions()
    end
end)

CreateThread(function()
    Wait(1500)
    TriggerServerEvent('humalike:npc:requestAmbientControls')
    while true do
        Wait(Config.AmbientControl.StandTaskRefreshMs)
        local applied = false
        for key, control in pairs(controls) do
            local npcId = ambientByControlKey[key]
            local entry = npcId and AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
            local ped = npcId and AmbientPeds and AmbientPeds[npcId] or nil
            if entry and ped and DoesEntityExist(ped) then
                local locallyOwned = NetworkHasControlOfEntity(ped)
                if control and control.mode == 'held' and locallyOwned then
                    if not IsActionControlled(ped) and not isDowned(npcId) then
                        setHeldReactionsBlocked(ped, true)
                        if initializedHoldByPed[ped] ~= key then
                            ClearPedTasks(ped)
                            initializedHoldByPed[ped] = key
                        end
                        if not faceController(ped, control) then
                            TaskStandStill(ped, Config.AmbientControl.StandTaskDurationMs)
                        end
                    end
                    applied = true
                elseif not locallyOwned then
                    initializedHoldByPed[ped] = nil
                end
            end
        end
        if not applied then Wait(1000) end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for npcId, ped in pairs(AmbientPeds or {}) do
        removeInteraction(npcId)
        silencePed(ped, false)
        initializedHoldByPed[ped] = nil
        if DoesEntityExist(ped) and NetworkHasControlOfEntity(ped) then
            setHeldReactionsBlocked(ped, false)
            ClearPedTasks(ped)
            TaskWanderStandard(ped, 10.0, 10)
        end
    end
    ambientByControlKey = {}
end)
