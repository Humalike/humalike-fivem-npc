function HumalikePlaceOrder(npcId, playerId, rawLines)
    playerId = tonumber(playerId)
    if not playerId or playerId <= 0 or playerId % 1 ~= 0 then
        return HumalikeExportResult.Failure('invalid_player')
    end
    if not HumalikePlayer.IsCharacterLoaded(playerId) then
        return HumalikeExportResult.Failure('character_not_loaded')
    end
    local target, targetError = HumalikeObservationTarget(npcId)
    if not target then return HumalikeExportResult.Failure(targetError or 'npc_not_found') end
    local catalog = HumalikeActions.Catalog()
    if not catalog then return HumalikeExportResult.Failure('no_catalog') end
    if type(rawLines) ~= 'table' or next(rawLines) == nil then
        return HumalikeExportResult.Failure('invalid_lines')
    end
    local lines, count = {}, 0
    for item, quantity in pairs(rawLines) do
        if type(item) ~= 'string' or not catalog.items[item] then
            return HumalikeExportResult.Failure(('unknown_item:%s'):format(tostring(item)))
        end
        quantity = type(quantity) == 'number' and math.tointeger(quantity) or nil
        if not quantity or quantity < 1 or quantity > 1000 then
            return HumalikeExportResult.Failure(('invalid_quantity:%s'):format(item))
        end
        lines[item] = quantity
        count = count + 1
        if count > 16 then return HumalikeExportResult.Failure('too_many_lines') end
    end
    HumalikePostPlayerEvent(playerId, {
        type = 'order_requested',
        npc_id = npcId,
        lease_token = target.lease_token,
        lines = lines,
    })
    HumalikeDebug('order requested at npc %s by player %d', npcId, playerId)
    return HumalikeExportResult.Success({ lines = lines })
end

exports('PlaceOrder', function(npcId, playerId, lines)
    return HumalikePlaceOrder(npcId, playerId, lines)
end)
