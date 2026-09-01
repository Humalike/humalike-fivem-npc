local REPORT_INTERVAL_MS = 500
local lastReportAt = {}

RegisterNetEvent('humalike:integration:esx:rpAction', function(kind, text)
    if HumalikePlayer.Name() ~= 'esx' or GetResourceState('esx_rpchat') ~= 'started' then return end
    local playerId = source
    local now = GetGameTimer()
    local previous = lastReportAt[playerId]
    if previous and now - previous < REPORT_INTERVAL_MS then return end
    if HumalikeReportPlayerEvent(playerId, { type = 'rp_action', kind = kind, text = text }) then
        lastReportAt[playerId] = now
    end
end)

AddEventHandler('playerDropped', function()
    lastReportAt[source] = nil
end)
