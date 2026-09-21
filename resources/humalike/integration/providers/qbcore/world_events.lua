local RESOURCE = 'qb-core'
local reports = HumalikeProviderUtils.PlayerRateLimit(500)

local function actionText(text)
    if type(text) ~= 'string' then return nil end
    text = text:gsub('[~<].-[>~]', ''):match('^%s*(.-)%s*$')
    return text ~= '' and text or nil
end

-- Client-reported on purpose: qb-core has no server-side hook for /me short of
-- wrapping its command. Any player may type /me with any text, so a forged
-- report gains nothing; the server still checks the sender, its loaded
-- character, the provider, the text and the rate.
RegisterNetEvent('humalike:integration:qbcore:rpAction', function(text)
    if HumalikePlayer.Name() ~= 'qbcore' or GetResourceState(RESOURCE) ~= 'started' then return end
    local playerId = source
    text = actionText(text)
    if not text or not reports.Allows(playerId) then return end
    if HumalikeReportPlayerEvent(playerId, { type = 'rp_action', kind = 'me', text = text }) then
        reports.Record(playerId)
    end
end)
