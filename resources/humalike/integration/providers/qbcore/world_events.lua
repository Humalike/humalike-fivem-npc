local RESOURCE = 'qb-core'
local REPORT_INTERVAL_MS = 500
local lastReportAt = {}

local function actionText(text)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('[~<].-[>~]', ''):match('^%s*(.-)%s*$')
    return text ~= '' and text or nil
end

RegisterNetEvent('humalike:integration:qbcore:rpAction', function(text)
    if HumalikePlayer.Name() ~= 'qbcore' or GetResourceState(RESOURCE) ~= 'started' then return end
    local playerId = source
    text = actionText(text)
    if not text then return end
    local now = GetGameTimer()
    local previous = lastReportAt[playerId]
    if previous and now - previous < REPORT_INTERVAL_MS then return end
    if HumalikeReportPlayerEvent(playerId, { type = 'rp_action', kind = 'me', text = text }) then
        lastReportAt[playerId] = now
    end
end)

AddEventHandler('playerDropped', function()
    lastReportAt[source] = nil
end)
