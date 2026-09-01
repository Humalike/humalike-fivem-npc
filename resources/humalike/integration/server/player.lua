HumalikePlayer = {}

function HumalikePlayer.Name()
    local provider = HumalikeSelectedProvider('player')
    return provider and provider.name or nil
end

function HumalikePlayer.GetCharacterId(source)
    local ok, value = HumalikeProviderCall('player', 'GetCharacterId', source)
    return ok and value or nil
end

function HumalikePlayer.GetCharacterName(source)
    local ok, value = HumalikeProviderCall('player', 'GetCharacterName', source)
    return ok and value or nil
end

function HumalikePlayer.IsCharacterLoaded(source)
    local ok, value = HumalikeProviderCall('player', 'IsCharacterLoaded', source)
    return ok and value == true
end

function HumalikePlayer.HasJob(source, names, requireDuty)
    if type(names) ~= 'table' or #names == 0 then return true end
    local ok, value = HumalikeProviderCall('player', 'HasJob', source, names,
        requireDuty == true)
    return ok and value == true
end

function HumalikePlayer.Notify(source, message, kind)
    local ok = HumalikeProviderCall('player', 'Notify', source, message, kind)
    return ok
end
