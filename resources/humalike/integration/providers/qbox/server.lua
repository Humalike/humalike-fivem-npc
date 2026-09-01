local RESOURCE = 'qbx_core'

local function player(source)
    return exports[RESOURCE]:GetPlayer(source)
end

HumalikeRegisterInternalProvider('player', {
    name = 'qbox',
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
        exports[RESOURCE]:Notify(source, message,
            HumalikeProviderUtils.NotificationKind(kind))
        return true
    end,
})
