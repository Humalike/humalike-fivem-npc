local reportedKey = nil
local failures = 0
local retryAt = 0

-- `set`, never `setr`: the flag is read on the server each reconcile tick.
local function groupSpawns()
    return GetConvar('humalike_group_spawns', 'true') == 'true'
end

function HumalikeNpcGroupSpawnsEnabled()
    return groupSpawns()
end

function HumalikeNpcFeatures()
    local features = {}
    if groupSpawns() then features[#features + 1] = 'group_scenes' end
    return features
end

-- Only a delivered report counts; a failed one is retried with backoff.
function HumalikeNpcFeaturesReported(features, ok)
    if ok then
        reportedKey = table.concat(features, ',')
        failures = 0
        return
    end
    local cfg = Config.Population
    retryAt = GetGameTimer() + math.min(cfg.RetryBackoffMs * (2 ^ math.min(failures, 10)),
        cfg.RetryBackoffCapMs)
    failures = failures + 1
end

-- A convar flip after the last report is re-posted at once, so the edge stops
-- (or starts) planning scenes without waiting for a runtime refresh.
function HumalikeNpcFeaturesTick()
    if reportedKey == nil or not HumalikeNpcReportCapabilities then return false end
    if table.concat(HumalikeNpcFeatures(), ',') == reportedKey then return false end
    if GetGameTimer() < retryAt then return false end
    if HumaLike and HumaLike.RuntimeCredentials and not HumaLike.RuntimeCredentials() then
        return false
    end
    HumalikeNpcReportCapabilities()
    return true
end
