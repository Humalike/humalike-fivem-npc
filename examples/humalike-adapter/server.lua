-- Stand-in for the server's inventory: wire `exports.ox_inventory:AddItem`
-- (or your own) here and return true only when the item was handed over.
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

    -- The server's one actions provider carries what the NPC can ask it to
    -- run (built-in deeds, its own deeds) and what it can observe. One
    -- provider owns all of it: HumaLike consults only the selected actions
    -- provider, so a second one registered just for observations or actions
    -- would shadow this one or leave the domain ambiguous.
    exports.humalike:RegisterProvider('actions', {
        name = 'example_actions',
        apiVersion = 1,
        priority = 100,
        SupportedActions = { 'hand_over_money' },
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
                -- Replace with your inventory's "give item" call; params.item is
                -- the fixed value above. Return true only once the item really
                -- moved: the NPC treats the return value as what happened.
                local given = giveItem(source, params.item, 1)
                if given then
                    TriggerClientEvent('chat:addMessage', source, {
                        args = { 'HumaLike', ('You received: %s'):format(params.item) },
                    })
                end
                return given == true
            end
            if action == 'hand_over_money' then
                -- Replace with your economy's "give cash to player" call and
                -- return true only once the cash really moved; the NPC treats
                -- the return value as what happened.
                print(('example adapter: no economy wired, %s for player %s (%s) not delivered'):format(
                    action, tostring(source), tostring(params.robber_description)))
                return false
            end
            return false
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

-- What each NPC has to give is the server's to set, once the roster is in:
-- the whole shelf every time, so restocking is calling it again. Deeds with
-- `uses_stock` and catalogue lines lock when an item runs out.
AddEventHandler('humalike:npc:ready', function()
    local npcId = 'replace-with-the-npc-uuid-from-the-dashboard'
    local result = exports.humalike:SetNpcStock(npcId, { treasure_map = 5, water = 'unlimited' })
    if not result.ok then
        print(('example adapter: stock rejected (%s)'):format(result.error))
    end
end)
