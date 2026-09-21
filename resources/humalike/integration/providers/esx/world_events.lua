local reports = HumalikeProviderUtils.PlayerRateLimit(500)

RegisterNetEvent('humalike:integration:esx:rpAction', function(kind, text)
    if HumalikePlayer.Name() ~= 'esx' or GetResourceState('esx_rpchat') ~= 'started' then return end
    local playerId = source
    if not reports.Allows(playerId) then return end
    if HumalikeReportPlayerEvent(playerId, { type = 'rp_action', kind = kind, text = text }) then
        reports.Record(playerId)
    end
end)
