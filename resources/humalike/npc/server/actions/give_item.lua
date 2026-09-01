local function isInteger(value)
    return type(value) == 'number' and value == math.floor(value)
end

local function isAllowedItem(itemName)
    if not Config.GiveItem.AllowlistEnabled then return true end
    return Config.GiveItem.AllowedItems[itemName] == true
end

local function giveItem(npcCoords, params)
    if type(params) ~= 'table'
        or not isInteger(params.player_id)
        or params.player_id < 1
        or type(params.item_name) ~= 'string'
        or params.item_name == ''
        or not isInteger(params.quantity)
        or params.quantity < 1
        or params.quantity > Config.GiveItem.MaxQuantity then
        HumalikeDebug('give_item: rejected invalid params')
        return false
    end

    if not isAllowedItem(params.item_name) then
        HumalikeDebug('give_item: item %q is not allowlisted', params.item_name)
        return false
    end

    local playerId = params.player_id
    if not GetPlayerName(playerId) or not HumalikePlayer.IsCharacterLoaded(playerId) then
        HumalikeDebug('give_item: player %s is unavailable', tostring(playerId))
        return false
    end

    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        HumalikeDebug('give_item: player %s has no server ped', tostring(playerId))
        return false
    end

    local playerCoords = GetEntityCoords(ped)
    local dx = playerCoords.x - npcCoords.x
    local dy = playerCoords.y - npcCoords.y
    local dz = playerCoords.z - npcCoords.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance > Config.GiveItem.MaxDistance then
        HumalikeDebug('give_item: player %s is %.2f units from npc (max %.2f)',
            tostring(playerId), distance, Config.GiveItem.MaxDistance)
        return false
    end

    local delivered = HumalikeInventory.AddItem(
        playerId, params.item_name, params.quantity)
    HumalikeDebug('give_item: player=%s item=%s quantity=%d delivered=%s',
        tostring(playerId), params.item_name, params.quantity, tostring(delivered))
    return delivered
end
AddEventHandler('humalike:npc:runGiveItemAction', function(npcCoords, params, respond)
    respond(giveItem(npcCoords, params))
end)
