local panelOpen = false
local transmitting = false
local mediaTransmitting = false
local pttPressed = false
local cabinEpoch = nil
local cabinRevision = -1
local cabinMembership = nil
local pttReleaseGeneration = 0
local stopping = false
local nuiReady = false
local nuiBootId = nil
local sessionRetryGeneration = 0
local PTT_RELEASE_TAIL_MS = 200
local PTT_COMMAND = '+humalike_voice_ptt'
local PTT_RELEASE_COMMAND = '-' .. PTT_COMMAND:sub(2)
local PTT_CONTROL = GetHashKey(PTT_COMMAND) | 0x80000000
local pttMappingBinding = ''
local pttNativeBinding = ''
local pttSharesNativeBinding = false
local directTargets = {}

HumalikeNpcDirectTargets.Subscribe(function(targetNpcIds)
    directTargets = targetNpcIds
    SendNUIMessage({ type = 'voice:targets', targetNpcIds = targetNpcIds })
end)

local function setMouthAnimation(ped, active)
    if ped <= 0 or not DoesEntityExist(ped) then return end
    if active then
        PlayFacialAnim(ped, 'mic_chatter', 'mp_facial')
    else
        local dictionary = IsPedMale(ped) and 'facials@gen_male@variations@normal'
            or 'facials@gen_female@variations@normal'
        PlayFacialAnim(ped, 'mood_normal_1', dictionary)
    end
end

local function boundValue(value)
    value = tostring(value or '')
    if not value:match('^[tb]_.+') then return '' end
    return value
end

local function refreshPttBindings()
    pttMappingBinding = boundValue(
        GetControlInstructionalButton(2, PTT_CONTROL, true))
    pttNativeBinding = boundValue(
        GetControlInstructionalButton(2, 249, true))
    pttSharesNativeBinding = pttMappingBinding ~= ''
        and pttMappingBinding == pttNativeBinding
end

local function sendBinding()
    refreshPttBindings()
    SendNUIMessage({ type = 'voice:keybind', binding = pttMappingBinding })
end

local function setTransmitting(active)
    if transmitting == active then return end
    transmitting = active
    SendNUIMessage({ type = 'voice:ptt', active = active })
    setMouthAnimation(PlayerPedId(), active)
end

local function requestSession()
    if stopping or not nuiReady then return end
    sessionRetryGeneration = sessionRetryGeneration + 1
    TriggerServerEvent('humalike:world:requestVoiceSession')
end

local function diagnosticValue(value, maxLength)
    value = tostring(value or ''):gsub('[%c]', ' ')
    return value:sub(1, maxLength)
end

local function sendLocale()
    SendNUIMessage({ type = 'voice:locale', language = HumalikeUiLanguage() })
end

local function syncNuiState()
    sendBinding()
    sendLocale()
    SendNUIMessage({ type = 'ui:setOpen', open = panelOpen })
    SendNUIMessage({ type = 'voice:ptt', active = transmitting })
    SendNUIMessage({ type = 'voice:targets', targetNpcIds = directTargets })
    local state = exports['humalike']:GetLocalPlayerState()
    if state then SendNUIMessage({ type = 'game:realtime', state = state }) end
    local listener = exports['humalike']:GetListenerState()
    if listener then
        SendNUIMessage({ type = 'game:listener', position = listener.position,
            forward = listener.forward })
    end
    local membership = exports['humalike']:GetCabinMembership(
        GetPlayerServerId(PlayerId()))
    cabinMembership = type(membership) == 'table' and membership or nil
    SendNUIMessage({ type = 'voice:cabin', active = cabinMembership ~= nil,
        membership = cabinMembership, epoch = cabinEpoch, revision = cabinRevision })
end

RegisterNUICallback('ready', function(data, callback)
    local bootId = diagnosticValue(type(data) == 'table' and data.bootId or '', 64)
    if bootId == '' or not bootId:match('^[%w_-]+$') then
        callback({ ok = false })
        return
    end
    local bootChanged = bootId ~= nuiBootId
    nuiBootId = bootId
    nuiReady = true
    callback({ ok = true })
    if bootChanged then
        HumalikeNpcDirectTargets.SetAvailable(false)
        syncNuiState()
        requestSession()
    end
end)

RegisterCommand('voice', function()
    panelOpen = not panelOpen
    SetNuiFocus(panelOpen, panelOpen)
    SendNUIMessage({ type = 'ui:setOpen', open = panelOpen })
    if panelOpen then sendBinding() end
end, false)

RegisterNUICallback('close', function(_, callback)
    panelOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'ui:setOpen', open = false })
    callback({ ok = true })
end)

RegisterNUICallback('requestSession', function(_, callback)
    requestSession()
    callback({ ok = true })
end)

RegisterNUICallback('actorSpeechState', function(data, callback)
    local actorId = type(data) == 'table' and data.id or nil
    if type(actorId) == 'string' and #actorId > 0 and #actorId <= 128
        and data.kind == 'npc' then
        TriggerEvent('humalike-voice:npcSpeaking', actorId, data.active == true)
    end
    callback({ ok = true })
end)

RegisterNUICallback('transmitState', function(data, callback)
    local active = type(data) == 'table' and data.active == true
    if mediaTransmitting ~= active then
        mediaTransmitting = active
        TriggerEvent('humalike:voice:transmittingChanged', active)
    end
    callback({ ok = true })
end)

RegisterNUICallback('directTargetCapability', function(data, callback)
    HumalikeNpcDirectTargets.SetAvailable(type(data) == 'table' and data.active == true)
    callback({ ok = true })
end)

exports('IsTransmitting', function()
    return mediaTransmitting
end)

exports('GetStatus', function()
    return {
        transmitting = transmitting,
        mediaTransmitting = mediaTransmitting,
        busy = HumalikeVoiceBusy.Reasons(),
        radioActive = HumalikeVoiceBusy.Has(':radio'),
        callActive = HumalikeVoiceBusy.Has(':call'),
        cabin = cabinMembership,
        cabinEpoch = cabinEpoch,
        cabinRevision = cabinRevision,
    }
end)

RegisterNetEvent('humalike:world:voiceSessionReady', function(session)
    sessionRetryGeneration = sessionRetryGeneration + 1
    SendNUIMessage({ type = 'voice:session', session = session })
    SendNUIMessage({ type = 'voice:ptt', active = transmitting })
end)

RegisterNetEvent('humalike:world:voiceSessionFailed', function(status)
    HumalikeNpcDirectTargets.SetAvailable(false)
    SendNUIMessage({ type = 'voice:sessionFailed', status = status })
    sessionRetryGeneration = sessionRetryGeneration + 1
    local generation = sessionRetryGeneration
    SetTimeout(1500, function()
        if not stopping and generation == sessionRetryGeneration then requestSession() end
    end)
end)

RegisterNetEvent('humalike:world:voiceReconnect', function()
    sessionRetryGeneration = sessionRetryGeneration + 1
    SendNUIMessage({ type = 'voice:reconnect' })
end)

RegisterNetEvent('humalike:world:cabinMembership', function(snapshot)
    if type(snapshot) ~= 'table' or type(snapshot.epoch) ~= 'string'
        or type(snapshot.revision) ~= 'number' then return end
    if cabinEpoch ~= snapshot.epoch then
        cabinEpoch = snapshot.epoch
        cabinRevision = -1
    end
    if snapshot.revision < cabinRevision then return end
    cabinRevision = snapshot.revision
    cabinMembership = type(snapshot.membership) == 'table' and snapshot.membership or nil
    SendNUIMessage({ type = 'voice:cabin', active = cabinMembership ~= nil,
        membership = cabinMembership, epoch = cabinEpoch, revision = cabinRevision })
end)

AddEventHandler('humalike:world:playerMotion', function(state)
    SendNUIMessage({ type = 'game:realtime', state = state })
end)

AddEventHandler('humalike:world:listener', function(listener)
    SendNUIMessage({
        type = 'game:listener',
        position = listener.position,
        forward = listener.forward,
    })
end)

AddEventHandler('humalike:settings:applied', sendLocale)

AddEventHandler('humalike:world:registrationRequested', function()
    requestSession()
end)

local function cancelPtt()
    pttPressed = false
    pttReleaseGeneration = pttReleaseGeneration + 1
    setTransmitting(false)
    HumalikeNpcDirectTargets.Unlock()
end

HumalikeVoiceBusy.Subscribe(function(busy)
    if busy then cancelPtt() end
end)

local keyPttActive = false

RegisterCommand(PTT_COMMAND, function() keyPttActive = true end, false)
RegisterCommand(PTT_RELEASE_COMMAND, function() keyPttActive = false end, false)
RegisterKeyMapping(PTT_COMMAND, 'Humalike AI voice PTT', 'keyboard', 'N')

CreateThread(function()
    while true do
        local controlPressed = HumalikeVoicePtt.InputPressed(
            keyPttActive,
            pttSharesNativeBinding,
            IsControlPressed(0, 249),
            IsDisabledControlPressed(0, 249),
            IsControlPressed(2, 249),
            IsDisabledControlPressed(2, 249))
        local pressed = HumalikeVoicePtt.Allowed(controlPressed, HumalikeVoiceBusy.Active())
        if pressed and not pttPressed then
            pttPressed = true
            pttReleaseGeneration = pttReleaseGeneration + 1
            HumalikeNpcDirectTargets.Lock()
            setTransmitting(true)
        elseif not pressed and pttPressed then
            pttPressed = false
            pttReleaseGeneration = pttReleaseGeneration + 1
            local generation = pttReleaseGeneration
            SetTimeout(PTT_RELEASE_TAIL_MS, function()
                if not pttPressed and generation == pttReleaseGeneration then
                    setTransmitting(false)
                    HumalikeNpcDirectTargets.Unlock()
                end
            end)
        end
        Wait(0)
    end
end)

CreateThread(function()
    Wait(500)
    refreshPttBindings()
    if nuiReady then syncNuiState() end
end)

CreateThread(function()
    while not stopping do
        Wait(2000)
        refreshPttBindings()
    end
end)

CreateThread(function()
    while not stopping do
        SendNUIMessage({ type = 'voice:bootstrap', language = HumalikeUiLanguage() })
        Wait(nuiReady and 10000 or 500)
    end
end)

CreateThread(function()
    while true do
        if panelOpen then sendBinding() end
        if transmitting then
            local ped = PlayerPedId()
            setMouthAnimation(ped, true)
        end
        Wait((panelOpen or transmitting) and 500 or 1500)
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    stopping = true
    pttPressed = false
    setTransmitting(false)
    HumalikeNpcDirectTargets.Unlock()
    HumalikeNpcDirectTargets.SetAvailable(false)
    mediaTransmitting = false
    TriggerEvent('humalike:voice:transmittingChanged', false)
    sessionRetryGeneration = sessionRetryGeneration + 1
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'voice:shutdown' })
end)
