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

    -- The server's one actions provider carries both what the NPC can ask it
    -- to run and what it can observe. One provider owns all observations:
    -- HumaLike consults only the selected actions provider, so a second one
    -- registered just for observations would shadow this one or leave the
    -- domain ambiguous.
    exports.humalike:RegisterProvider('actions', {
        name = 'example_actions',
        apiVersion = 1,
        priority = 100,
        SupportedActions = { 'hand_over_money' },
        RunAction = function(action, source, _npcCoords, params)
            if action ~= 'hand_over_money' then return false end
            -- Replace with your economy's "give cash to player" call and
            -- return true only once the cash really moved; the NPC treats
            -- the return value as what happened.
            print(('example adapter: no economy wired, %s for player %s (%s) not delivered'):format(
                action, tostring(source), tostring(params.robber_description)))
            return false
        end,
        -- Facts only this server knows. Declare them once; report each
        -- occurrence from the hook that makes it true (see below).
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
