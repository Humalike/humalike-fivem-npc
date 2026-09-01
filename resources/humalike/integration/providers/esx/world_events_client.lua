RegisterNetEvent('esx_rpchat:sendProximityMessage', function(playerId, _, text, color)
    if playerId ~= GetPlayerServerId(PlayerId()) or type(color) ~= 'table' then return end
    local kind
    if color[1] == 255 and color[2] == 0 and color[3] == 0 then
        kind = 'me'
    elseif color[1] == 0 and color[2] == 0 and color[3] == 255 then
        kind = 'do'
    end
    if kind then TriggerServerEvent('humalike:integration:esx:rpAction', kind, text) end
end)
