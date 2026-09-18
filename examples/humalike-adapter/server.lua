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

    -- Facts only this server knows. Declare them once; report each occurrence
    -- from the hook that makes it true (see below).
    exports.humalike:RegisterProvider('actions', {
        name = 'example_actions',
        apiVersion = 1,
        priority = 100,
        SupportedActions = {},
        Namespace = 'example',
        Observations = {
            item_given = {
                fields = { item = 'string', quantity = 'integer' },
                template = {
                    en = 'the character handed you {quantity} x {item}',
                    pl = 'postać wręczyła ci {quantity} x {item}',
                },
            },
        },
    })
end

-- Replace with your inventory's "gave item to ped" event. Report only after
-- the transfer really happened; the NPC treats this as fact.
AddEventHandler('example:inventory:itemGivenToNpc', function(source, npcId, item, quantity)
    local result = exports.humalike:ReportObservation(npcId, source, 'item_given', {
        item = item,
        quantity = quantity,
    })
    if not result.ok then
        print(('example adapter: observation rejected (%s)'):format(result.error))
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then registerProviders() end
end)

AddEventHandler('humalike:integration:ready', registerProviders)
