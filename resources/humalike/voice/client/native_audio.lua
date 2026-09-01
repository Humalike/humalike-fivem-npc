HumalikeVoiceNativeAudio = {
    desired = {},
    overridden = {},
    callPlayers = {},
    radioPlayers = {},
    lastSnapshotAt = 0,
}

local function pmaStarted()
    return GetResourceState('pma-voice') == 'started'
end

local function pmaMuted(serverId)
    if not pmaStarted() then return false end
    local ok, muted = pcall(function()
        return exports['pma-voice']:isPlayerMuted(serverId)
    end)
    return ok and muted == true
end

local function protected(serverId)
    return HumalikeVoiceNativeAudio.callPlayers[serverId]
        or HumalikeVoiceNativeAudio.radioPlayers[serverId]
end

local function release(serverId)
    if not HumalikeVoiceNativeAudio.overridden[serverId] then return end
    HumalikeVoiceNativeAudio.overridden[serverId] = nil
    if protected(serverId) then return end
    MumbleSetVolumeOverrideByServerId(serverId, pmaMuted(serverId) and 0.0 or -1.0)
end

local function reconcile(serverId, reassert)
    if HumalikeVoiceNativeAudio.desired[serverId] and not protected(serverId)
        and pmaStarted() then
        if reassert or not HumalikeVoiceNativeAudio.overridden[serverId] then
            MumbleSetVolumeOverrideByServerId(serverId, 0.0)
        end
        HumalikeVoiceNativeAudio.overridden[serverId] = true
    else
        release(serverId)
    end
end

local function reconcileAll(reassert)
    local players = {}
    for serverId in pairs(HumalikeVoiceNativeAudio.desired) do players[serverId] = true end
    for serverId in pairs(HumalikeVoiceNativeAudio.overridden) do players[serverId] = true end
    for serverId in pairs(players) do reconcile(serverId, reassert) end
end

function HumalikeVoiceNativeAudio.UpdateSnapshot(players)
    local nextPlayers = {}
    if type(players) == 'table' then
        for index, value in ipairs(players) do
            if index > 128 then break end
            local serverId = tonumber(value)
            if serverId and serverId > 0 and serverId % 1 == 0
                and serverId ~= GetPlayerServerId(PlayerId()) then
                nextPlayers[serverId] = true
            end
        end
    end
    HumalikeVoiceNativeAudio.desired = nextPlayers
    HumalikeVoiceNativeAudio.lastSnapshotAt = GetGameTimer()
    reconcileAll(true)
end

function HumalikeVoiceNativeAudio.RestoreAll()
    local overridden = HumalikeVoiceNativeAudio.overridden
    HumalikeVoiceNativeAudio.overridden = {}
    for serverId in pairs(overridden) do
        if not protected(serverId) then
            MumbleSetVolumeOverrideByServerId(serverId, pmaMuted(serverId) and 0.0 or -1.0)
        end
    end
end

local function replaceProtected(target, values, activeValuesOnly)
    local previous = HumalikeVoiceNativeAudio[target]
    local nextValues = {}
    if type(values) == 'table' then
        for rawServerId, active in pairs(values) do
            local serverId = tonumber(rawServerId)
            if serverId and serverId > 0 and (not activeValuesOnly or active == true) then
                nextValues[serverId] = true
            end
        end
    end
    HumalikeVoiceNativeAudio[target] = nextValues
    for serverId in pairs(previous) do
        if not nextValues[serverId] then reconcile(serverId, true) end
    end
    for serverId in pairs(nextValues) do reconcile(serverId, false) end
end

function HumalikeVoiceNativeAudio.Status()
    local desired, overridden = 0, 0
    for _ in pairs(HumalikeVoiceNativeAudio.desired) do desired = desired + 1 end
    for _ in pairs(HumalikeVoiceNativeAudio.overridden) do overridden = overridden + 1 end
    return {
        desired = desired,
        overridden = overridden,
        pmaStarted = pmaStarted(),
        lastSnapshotAt = HumalikeVoiceNativeAudio.lastSnapshotAt,
    }
end

RegisterNetEvent('pma-voice:syncCallData')
AddEventHandler('pma-voice:syncCallData', function(players)
    replaceProtected('callPlayers', players, false)
end)
RegisterNetEvent('pma-voice:addPlayerToCall')
AddEventHandler('pma-voice:addPlayerToCall', function(rawServerId)
    local serverId = tonumber(rawServerId)
    if not serverId then return end
    HumalikeVoiceNativeAudio.callPlayers[serverId] = true
    reconcile(serverId, false)
end)
RegisterNetEvent('pma-voice:removePlayerFromCall')
AddEventHandler('pma-voice:removePlayerFromCall', function(rawServerId)
    local serverId = tonumber(rawServerId)
    if not serverId then return end
    if serverId == GetPlayerServerId(PlayerId()) then
        local previous = HumalikeVoiceNativeAudio.callPlayers
        HumalikeVoiceNativeAudio.callPlayers = {}
        SetTimeout(0, function()
            for playerId in pairs(previous) do reconcile(playerId, true) end
        end)
    else
        HumalikeVoiceNativeAudio.callPlayers[serverId] = nil
        SetTimeout(0, function() reconcile(serverId, true) end)
    end
end)
RegisterNetEvent('pma-voice:syncRadioData')
AddEventHandler('pma-voice:syncRadioData', function(players)
    replaceProtected('radioPlayers', players, true)
end)
RegisterNetEvent('pma-voice:removePlayerFromRadio')
AddEventHandler('pma-voice:removePlayerFromRadio', function(rawServerId)
    local serverId = tonumber(rawServerId)
    if not serverId then return end
    HumalikeVoiceNativeAudio.radioPlayers[serverId] = nil
    SetTimeout(0, function() reconcile(serverId, true) end)
end)
RegisterNetEvent('pma-voice:setTalkingOnRadio')
AddEventHandler('pma-voice:setTalkingOnRadio', function(rawServerId, active)
    local serverId = tonumber(rawServerId)
    if not serverId then return end
    HumalikeVoiceNativeAudio.radioPlayers[serverId] = active == true or nil
    SetTimeout(0, function() reconcile(serverId, active ~= true) end)
end)

RegisterNetEvent('onPlayerDropped')
AddEventHandler('onPlayerDropped', function(rawServerId)
    local serverId = tonumber(rawServerId)
    if not serverId then return end
    HumalikeVoiceNativeAudio.callPlayers[serverId] = nil
    HumalikeVoiceNativeAudio.radioPlayers[serverId] = nil
    HumalikeVoiceNativeAudio.desired[serverId] = nil
    release(serverId)
end)

CreateThread(function()
    while true do
        Wait(250)
        if next(HumalikeVoiceNativeAudio.desired)
            and GetGameTimer() - HumalikeVoiceNativeAudio.lastSnapshotAt > 1250 then
            HumalikeVoiceNativeAudio.desired = {}
            HumalikeVoiceNativeAudio.RestoreAll()
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        HumalikeVoiceNativeAudio.desired = {}
        HumalikeVoiceNativeAudio.RestoreAll()
    elseif resource == 'pma-voice' then
        HumalikeVoiceNativeAudio.callPlayers = {}
        HumalikeVoiceNativeAudio.radioPlayers = {}
        HumalikeVoiceNativeAudio.RestoreAll()
    end
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= 'pma-voice' then return end
    HumalikeVoiceNativeAudio.callPlayers = {}
    HumalikeVoiceNativeAudio.radioPlayers = {}
    SetTimeout(0, function() reconcileAll(true) end)
end)
