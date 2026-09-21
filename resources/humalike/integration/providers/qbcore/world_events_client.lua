-- qb-core broadcasts every /me to nearby players, the sender included; the
-- sender's own copy is reported so qb-core's command table stays untouched.
RegisterNetEvent('QBCore:Command:ShowMe3D', function(playerId, text)
    if playerId ~= GetPlayerServerId(PlayerId()) or type(text) ~= 'string' then return end
    TriggerServerEvent('humalike:integration:qbcore:rpAction', text)
end)
