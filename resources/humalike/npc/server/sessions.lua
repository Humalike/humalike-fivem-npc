
local appearances = {}
local pendingAppearanceUpserts = {}
local publishedIdentities = {}

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function identity(playerId)
    playerId = tonumber(playerId)
    if not playerId or not HumalikePlayer.IsCharacterLoaded(playerId) then return nil end
    local characterId = HumalikePlayer.GetCharacterId(playerId)
    if not characterId then return nil end
    local current = {
        characterId = tostring(characterId),
        name = HumalikePlayer.GetCharacterName(playerId)
            or GetPlayerName(playerId) or tostring(characterId),
    }
    local appearance = appearances[tostring(playerId)]
    if appearance then
        local ped = GetPlayerPed(playerId)
        if ped and ped > 0 and DoesEntityExist(ped) then
            current.appearance = {
                model = unsignedHash(GetEntityModel(ped)),
                components = appearance.components,
                props = appearance.props,
                features = appearance.features,
            }
        end
    end
    return current
end

local function publishIdentity(playerId, force)
    local current = identity(playerId)
    if not current then return false end
    local payload = {
        characterId = current.characterId,
        name = current.name,
        metadata = { npc = { appearance = current.appearance } },
    }
    local key, encoded = tostring(playerId), json.encode(payload)
    if not force and publishedIdentities[key] == encoded then return true end
    local ok = exports['humalike']:SetPlayerIdentity(playerId, payload)
    if ok then publishedIdentities[key] = encoded end
    return ok
end

AddEventHandler('playerDropped', function()
    local playerId = source
    local key = tostring(playerId)
    appearances[key] = nil
    pendingAppearanceUpserts[key] = nil
    publishedIdentities[key] = nil
end)

local reportablePropIds, maxPropId = {}, 0
for _, propId in ipairs(Config.AppearancePropIds) do
    reportablePropIds[propId] = true
    if propId > maxPropId then maxPropId = propId end
end

local function validInt(value, min, max)
    return type(value) == 'number' and value % 1 == 0 and value >= min and value <= max
end
local function validTriples(entries, maxEntries, maxId, allowedIds)
    if type(entries) ~= 'table' then return nil end
    local maxValue = Config.AppearanceMaxDrawableId
    local sorted = {}
    for _, entry in ipairs(entries) do
        if #sorted >= maxEntries or type(entry) ~= 'table'
            or not validInt(entry[1], 0, maxId)
            or allowedIds and not allowedIds[entry[1]]
            or not validInt(entry[2], 0, maxValue)
            or not validInt(entry[3], 0, maxValue) then return nil end
        sorted[#sorted + 1] = { entry[1], entry[2], entry[3] }
    end
    table.sort(sorted, function(a, b) return a[1] < b[1] end)
    for index = 2, #sorted do
        if sorted[index][1] == sorted[index - 1][1] then return nil end
    end
    return sorted
end
local FEATURE_COUNT = 9
local featureUpperBounds = { 45, 45, 10, 255, 255, 255, 10, 255, 255 }
local function validFeatures(entries)
    if type(entries) ~= 'table' or #entries ~= FEATURE_COUNT then return nil end
    local copied = {}
    for index = 1, FEATURE_COUNT do
        local value = entries[index]
        if not validInt(value, 0, featureUpperBounds[index]) then return nil end
        copied[index] = value
    end
    return copied
end

RegisterNetEvent('humalike:npc:appearanceChanged')
AddEventHandler('humalike:npc:appearanceChanged', function(components, props, features)
    local playerId = tonumber(source)
    if not playerId or playerId <= 0 or playerId % 1 ~= 0 then return end
    components = validTriples(components, 12, 11)
    props = validTriples(props, #Config.AppearancePropIds, maxPropId, reportablePropIds)
    if not components or #components ~= 12 or not props then return end
    local key = tostring(playerId)
    -- false clears features after a model swap; nil preserves a transient read failure.
    if features == false then
        features = nil
    elseif features ~= nil then
        features = validFeatures(features)
        if not features then features = nil end
    else
        local previous = appearances[key]
        features = previous and previous.features
    end
    appearances[key] = { components = components, props = props, features = features }
    -- One trailing timer per player bounds report bursts.
    if pendingAppearanceUpserts[key] then return end
    pendingAppearanceUpserts[key] = true
    SetTimeout(Config.AppearanceUpsertDebounceMs, function()
        if not pendingAppearanceUpserts[key] then return end
        pendingAppearanceUpserts[key] = nil
        publishIdentity(playerId)
    end)
end)

AddEventHandler('humalike:world:registrationRequested', function()
    publishedIdentities = {}
    for _, playerId in ipairs(GetPlayers()) do publishIdentity(playerId, true) end
end)

exports('RefreshPlayerIdentity', function(playerId) return publishIdentity(playerId, true) end)

CreateThread(function()
    while true do
        for _, playerId in ipairs(GetPlayers()) do
            -- One bad provider/native read must not stop periodic identity sync.
            local ok, err = pcall(publishIdentity, playerId)
            if not ok then
                print(('[humalike-npc] identity publish failed for player %s: %s')
                    :format(tostring(playerId), tostring(err)))
            end
        end
        Wait(Config.PlayerSessionSyncIntervalMs)
    end
end)

AddEventHandler('humalike:providers:changed', function(domain)
    if domain ~= 'framework' then return end
    publishedIdentities = {}
    for _, playerId in ipairs(GetPlayers()) do publishIdentity(playerId, true) end
end)
