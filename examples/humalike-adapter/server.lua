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

    -- Facts only this server knows, and deeds of its own gated on them.
    -- Declare once; report each fact from the hook that makes it true (see
    -- below); perform each deed in RunAction.
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
        Actions = {
            give_map = {
                name = 'Give the treasure map',
                description = 'Hand the player the map to the hidden chest.',
                fixed = { item = 'treasure_map' },
                requires = {
                    { observation = 'item_given', where = { item = 'amulet' }, consume = true },
                },
                locked_hint = {
                    en = 'Only once the amulet is in your hands.',
                    pl = 'Dopiero gdy amulet będzie w twoich rękach.',
                },
            },
        },
        RunAction = function(action, source, _npcCoords, params)
            if action ~= 'give_map' then return false end
            -- Replace with your inventory: params.item is the fixed value above.
            TriggerClientEvent('chat:addMessage', source, {
                args = { 'HumaLike', ('You received: %s'):format(params.item) },
            })
            return true
        end,
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
