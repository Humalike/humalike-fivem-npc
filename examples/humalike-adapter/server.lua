-- Replace with the server's inventory; return true only once the item moved.
local function giveItem(_source, _item, _count)
    return false
end

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

    exports.humalike:RegisterProvider('actions', {
        name = 'example_actions',
        apiVersion = 1,
        priority = 100,
        SupportedActions = { 'hand_over_money' },
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
            if action == 'give_map' then
                local given = giveItem(source, params.item, 1)
                if given then
                    TriggerClientEvent('chat:addMessage', source, {
                        args = { 'HumaLike', ('You received: %s'):format(params.item) },
                    })
                end
                return given == true
            end
            if action == 'hand_over_money' then
                -- Return true only once the cash really moved.
                print(('example adapter: no economy wired, %s for player %s (%s) not delivered'):format(
                    action, tostring(source), tostring(params.robber_description)))
                return false
            end
            return false
        end,
    })
end

-- Report only after the transfer really happened.
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
