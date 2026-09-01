local function registerProviders()
    exports.humalike:RegisterProvider('player', {
        name = 'example_player',
        apiVersion = 1,
        priority = 100,
        Available = function()
            return true
        end,
        GetCharacterId = function(source)
            return tostring(source)
        end,
        GetCharacterName = function(source)
            return GetPlayerName(source)
        end,
        IsCharacterLoaded = function(source)
            return GetPlayerName(source) ~= nil
        end,
        HasJob = function(_source, _jobNames, _requireDuty)
            return false
        end,
        Notify = function(source, message)
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'HumaLike', message },
            })
        end,
    })
end

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then registerProviders() end
end)

AddEventHandler('humalike:integration:ready', registerProviders)
