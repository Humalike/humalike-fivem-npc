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

    -- No framework, so a job is an ACE grant: `add_ace group.ems humalike.job.ambulance allow`.
    -- ACE has no duty state; a granted job counts as on duty.
    HasJob = function(source, names)
        for _, name in ipairs(names) do
            if IsPlayerAceAllowed(source, 'humalike.job.' .. name) then return true end
        end
        return false
    end,

    Notify = function(source, message)
        if type(message) ~= 'string' or message == '' then return end
        TriggerClientEvent('chat:addMessage', source, { args = { 'HumaLike', message } })
    end,
})
