AddStateBagChangeHandler('me', nil, function(bagName, _, value)
    if HumalikePlayer.Name() ~= 'qbox' or type(value) ~= 'string' or value == '' then return end
    local playerId = GetPlayerFromStateBagName(bagName)
    if not playerId or playerId <= 0 then return end
    HumalikeReportPlayerEvent(playerId, { type = 'rp_action', kind = 'me', text = value })
end)
