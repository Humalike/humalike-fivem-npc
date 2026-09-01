local function licenseIdentifier(source)
    for _, identifier in ipairs(GetPlayerIdentifiers(source)) do
        if identifier:sub(1, 8) == 'license:' then return identifier end
    end
    return nil
end

HumalikeRegisterInternalProvider('player', {
    name = 'standalone',
    apiVersion = 1,
    priority = -1000,

    GetCharacterId = function(source)
        return licenseIdentifier(source)
    end,

    GetCharacterName = function(source)
        return GetPlayerName(source)
    end,

    IsCharacterLoaded = function(source)
        return GetPlayerName(source) ~= nil
    end,

    HasJob = function(_source, _names)
        return false
    end,

    Notify = function(source, message)
        if type(message) ~= 'string' or message == '' then return end
        TriggerClientEvent('chat:addMessage', source, { args = { 'HumaLike', message } })
    end,
})
