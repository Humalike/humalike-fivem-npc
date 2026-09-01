local RESOURCE = 'qb-core'

local function core()
    return exports[RESOURCE]:GetCoreObject()
end

local function player(source)
    local framework = core()
    return framework and framework.Functions and framework.Functions.GetPlayer(source) or nil
end

HumalikeRegisterInternalProvider('player', {
    name = 'qbcore',
    apiVersion = 1,
    priority = 100,

    Available = function()
        return HumalikeProviderUtils.Started(RESOURCE)
    end,

    GetCharacterId = function(source)
        local current = player(source)
        return current and current.PlayerData and current.PlayerData.citizenid or nil
    end,

    GetCharacterName = function(source)
        local current = player(source)
        return HumalikeProviderUtils.CharacterName(current and current.PlayerData)
    end,

    IsCharacterLoaded = function(source)
        return player(source) ~= nil
    end,

    HasJob = function(source, names, requireDuty)
        local current = player(source)
        return HumalikeProviderUtils.HasJob(
            current and current.PlayerData and current.PlayerData.job,
            names, requireDuty, true)
    end,

    Notify = function(source, message, kind)
        local framework = core()
        if not framework or not framework.Functions
            or not HumalikeProviderUtils.Callable(framework.Functions.Notify) then return false end
        local notifyKind = HumalikeProviderUtils.NotificationKind(kind)
        framework.Functions.Notify(source, message,
            (notifyKind == 'success' or notifyKind == 'error') and notifyKind or 'primary')
        return true
    end,
})
