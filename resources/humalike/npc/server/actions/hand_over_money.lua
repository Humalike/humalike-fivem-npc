
local function isInteger(value)
    return type(value) == 'number' and value == math.floor(value)
end

local function handOverMoney(npcCoords, params)
    if type(params) ~= 'table' or not isInteger(params.player_id) or params.player_id < 1 then
        HumalikeDebug('hand_over_money: rejected invalid params')
        return false
    end

    local playerId = params.player_id
    if not GetPlayerName(playerId) or not HumalikePlayer.IsCharacterLoaded(playerId) then
        HumalikeDebug('hand_over_money: player %s is unavailable', tostring(playerId))
        return false
    end

    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        HumalikeDebug('hand_over_money: player %s has no server ped', tostring(playerId))
        return false
    end

    local playerCoords = GetEntityCoords(ped)
    local dx = playerCoords.x - npcCoords.x
    local dy = playerCoords.y - npcCoords.y
    local dz = playerCoords.z - npcCoords.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance > Config.Robbery.MaxDistance then
        HumalikeDebug('hand_over_money: player %s is %.2f units from npc (max %.2f)',
            tostring(playerId), distance, Config.Robbery.MaxDistance)
        return false
    end
    local description = type(params.robber_description) == 'string'
        and params.robber_description or nil
    local delivered = HumalikeActions.Run('hand_over_money', playerId, npcCoords, {
        robber_description = description,
    })
    HumalikeDebug('hand_over_money: player=%s delivered=%s', tostring(playerId), tostring(delivered))
    return delivered
end
AddEventHandler('humalike:npc:runHandOverMoneyAction', function(npcCoords, params, respond)
    respond(handOverMoney(npcCoords, params))
end)
