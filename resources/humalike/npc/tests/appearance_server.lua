local handlers = {}
local posts = {}
local timers = {}
local thread
local entityExists = true
local exported = {}
local latestIdentity

Config = {
    PlayerSessionSyncIntervalMs = 15000,
    AppearancePollIntervalMs = 1000,
    AppearanceUpsertDebounceMs = 750,
    AppearancePropIds = { 0, 1, 2, 6, 7 },
    AppearanceMaxDrawableId = 65535,
}
HumalikePlayer = {
    IsCharacterLoaded = function() return true end,
    GetCharacterId = function(playerId) return 100 + playerId end,
    GetCharacterName = function(playerId) return 'Player' .. playerId end,
}

source = 7

function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
function CreateThread(callback) thread = callback end
function Wait()
    if latestIdentity then
        posts[#posts + 1] = {
            action = 'sync_player_sessions',
            payload = {
                players = {
                    ['7'] = {
                        character_id = latestIdentity.characterId,
                        name = latestIdentity.name,
                        appearance = latestIdentity.metadata.npc.appearance,
                    },
                },
            },
        }
    end
    error('done')
end
function SetTimeout(delay, callback) timers[#timers + 1] = { delay = delay, callback = callback } end
function GetPlayers() return { '7' } end
function GetPlayerName(playerId) return 'Player' .. playerId end
function GetPlayerRoutingBucket() return 0 end
function GetPlayerPed(playerId) return playerId == 7 and 42 or 0 end
function GetEntityModel(entity) return entity == 42 and -2084633992 or 0 end
function DoesEntityExist(entity) return entityExists and entity == 42 end
function TriggerClientEvent() end

local function flushTimers()
    while #timers > 0 do table.remove(timers, 1).callback() end
end

local function serialize(value)
    if type(value) ~= 'table' then return ('%q'):format(tostring(value)) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key) .. '=' .. serialize(value[key])
    end
    return '{' .. table.concat(parts, ',') .. '}'
end
json = { encode = serialize }

HumalikeHttp = {
    PostAction = function(action, payload, callback)
        posts[#posts + 1] = { action = action, payload = payload }
        if callback then callback(true, 200, { ok = true }) end
    end,
}

exports = setmetatable({}, {
    __call = function(_, name, callback) exported[name] = callback end,
    __index = function(_, resource)
        assert(resource == 'humalike')
        return {
            SetPlayerIdentity = function(_, _, identity)
                latestIdentity = identity
                posts[#posts + 1] = {
                    action = 'upsert_player_session',
                    payload = {
                        fivem_session_id = 7,
                        character_id = identity.characterId,
                        name = identity.name,
                        appearance = identity.metadata.npc.appearance,
                    },
                }
                return true
            end,
        }
    end,
})

dofile('server/sessions.lua')
handlers['onPlayerBucketChange'] = function(playerId)
    SetTimeout(0, function() exported.RefreshPlayerIdentity(playerId) end)
end

local report = handlers['humalike:npc:appearanceChanged']
assert(report)

local function fullComponents(overrides)
    local list = {}
    for componentId = 0, 11 do list[componentId + 1] = { componentId, 0, 0 } end
    for index, entry in pairs(overrides or {}) do list[index] = entry end
    return list
end
handlers['onPlayerBucketChange'](7)
flushTimers()
assert(#posts == 1 and posts[1].action == 'upsert_player_session')
assert(posts[1].payload.appearance == nil)
local components = {
    { 11, 0, 0 }, { 10, 0, 0 }, { 9, 0, 0 }, { 8, 0, 0 }, { 7, 0, 0 }, { 6, 1, 0 },
    { 5, 0, 0 }, { 4, 7, 2 }, { 3, 0, 0 }, { 2, 0, 0 }, { 1, 0, 0 }, { 0, 0, 0 },
}
report(components, { { 7, 2, 0 }, { 0, 13, 1 } })
assert(#posts == 1 and #timers == 1 and timers[1].delay == 750) -- debounced, not immediate
flushTimers()
assert(#posts == 2 and posts[2].action == 'upsert_player_session')
local appearance = posts[2].payload.appearance
assert(appearance and appearance.model == 2210333304)
assert(#appearance.components == 12)
for index, entry in ipairs(appearance.components) do
    assert(entry[1] == index - 1)
end
assert(appearance.components[5][2] == 7 and appearance.components[5][3] == 2)
assert(#appearance.props == 2)
assert(appearance.props[1][1] == 0 and appearance.props[1][2] == 13
    and appearance.props[1][3] == 1)
assert(appearance.props[2][1] == 7 and appearance.props[2][2] == 2)
assert(appearance.features == nil)
assert(not serialize(appearance):find('features'))
report(components, { { 7, 2, 0 }, { 0, 13, 1 } })
flushTimers()
assert(#posts == 2)
report(fullComponents({ [5] = { 4, 7, 5 } }), {})
report(fullComponents({ [5] = { 4, 7, 6 } }), {})
assert(#timers == 1)
flushTimers()
assert(#posts == 3)
assert(posts[3].payload.appearance.components[5][3] == 6)
assert(#posts[3].payload.appearance.props == 0) -- empty props are valid: bare-headed
local valid12 = fullComponents()
local bad = {
    { nil, { { 0, 13, 0 } } },                              -- components not a table
    { 'x', {} },                                            -- components wrong type
    { {}, {} },                                             -- empty components
    { valid12, 'x' },                                       -- props wrong type
    { { { 0, 1, 0 } }, { { 3, 1, 0 } } },                   -- prop id 3 not reportable
    { fullComponents({ [12] = { 12, 1, 0 } }), {} },        -- component id out of range
    { fullComponents({ [1] = { 0, 65536, 0 } }), {} },      -- drawable above bound
    { fullComponents({ [1] = { 0, 1, 65536 } }), {} },      -- texture above bound
    { fullComponents({ [1] = { 0, 1, -1 } }), {} },         -- negative texture
    { fullComponents({ [1] = { 0, 1.5, 0 } }), {} },        -- non-integer drawable
    { fullComponents({ [1] = { 0, '1', 0 } }), {} },        -- non-numeric drawable
    { fullComponents({ [1] = { 0, 1 } }), {} },             -- missing texture
    { fullComponents({ [1] = 5 }), {} },                    -- entry not a table
    { fullComponents({ [2] = { 0, 2, 0 } }), {} },          -- duplicate component id
    { valid12, { { 0, 1, 0 }, { 0, 2, 0 } } },              -- duplicate prop id
    { valid12, { { 0, 1, 0 }, { 1, 1, 0 }, { 2, 1, 0 }, { 6, 1, 0 }, { 7, 1, 0 },
        { 7, 2, 0 } } },                                    -- more than 5 props
}
local partial = fullComponents()
partial[12] = nil                                           -- 11 components only
bad[#bad + 1] = { partial, {} }
local oversized = {}
for index = 1, 13 do oversized[index] = { (index - 1) % 12, 0, 0 } end
bad[#bad + 1] = { oversized, {} }                           -- more than 12 components
for _, case in ipairs(bad) do
    report(case[1], case[2])
end
flushTimers()
assert(#posts == 3)
report(fullComponents({ [1] = { 0, 30000, 65535 }, [2] = { 1, 2001, 0 } }),
    { { 2, 65535, 65535 } })
flushTimers()
assert(#posts == 4)
appearance = posts[4].payload.appearance
assert(appearance.components[1][2] == 30000 and appearance.components[1][3] == 65535)
assert(appearance.components[2][2] == 2001)
assert(appearance.props[1][1] == 2 and appearance.props[1][2] == 65535)
entityExists = false
handlers['onPlayerBucketChange'](7)
flushTimers()
assert(#posts == 5 and posts[5].payload.appearance == nil)
entityExists = true
pcall(thread)
assert(posts[#posts].action == 'sync_player_sessions')
local synced = posts[#posts].payload.players['7']
assert(synced and synced.appearance)
assert(synced.appearance.model == 2210333304)
assert(#synced.appearance.components == 12 and synced.appearance.components[1][2] == 30000)
assert(#synced.appearance.props == 1 and synced.appearance.props[1][1] == 2)
assert(synced.appearance.features == nil) -- nothing reported yet
local features = { 21, 2, 3, 5, 0, 10, 8, 3, 4 }
report(fullComponents({ [5] = { 4, 7, 2 } }), {}, features)
flushTimers()
assert(#posts == 8 and posts[8].action == 'upsert_player_session')
appearance = posts[8].payload.appearance
assert(appearance.features and #appearance.features == 9)
for index, value in ipairs({ 21, 2, 3, 5, 0, 10, 8, 3, 4 }) do
    assert(appearance.features[index] == value)
end
features[9] = 31
assert(appearance.features[9] == 4)
report(fullComponents({ [5] = { 4, 7, 2 } }), {}, { 21, 2, 3, 5, 0, 10, 8, 3, 9 })
flushTimers()
assert(#posts == 9 and posts[9].payload.appearance.features[9] == 9)
report(fullComponents({ [5] = { 4, 8, 0 } }), {})
flushTimers()
assert(#posts == 10)
assert(posts[10].payload.appearance.components[5][2] == 8)
assert(posts[10].payload.appearance.features[9] == 9)
local badFeatures = {
    { 21, 2, 3, 5, 0, 10, 8, 3 },              -- 8 ints
    { 21, 2, 3, 5, 0, 10, 8, 3, 4, 0 },        -- 10 ints
    { -1, 2, 3, 5, 0, 10, 8, 3, 4 },           -- negative
    { 21, 2, 3, 5.5, 0, 10, 8, 3, 4 },         -- non-integer
    { 21, 2, 3, '5', 0, 10, 8, 3, 4 },         -- non-numeric
    { 46, 2, 3, 5, 0, 10, 8, 3, 4 },           -- skin parent above 45
    { 21, 46, 3, 5, 0, 10, 8, 3, 4 },          -- second parent above 45
    { 21, 2, 11, 5, 0, 10, 8, 3, 4 },          -- mix tenths above 10
    { 21, 2, 3, 5, 0, 10, 11, 3, 4 },          -- opacity tenths above 10
    { 21, 2, 3, 256, 0, 10, 8, 3, 4 },         -- byte position above 255
    { 21, 2, 3, 5, 0, 10, 8, 3, 65535 },       -- the live unset eye color
    'x',                                       -- not a table
}
for index, case in ipairs(badFeatures) do
    report(fullComponents({ [5] = { 4, 9, index } }), {}, case)
    flushTimers()
    local last = posts[#posts]
    assert(#posts == 10 + index)
    assert(last.payload.appearance.components[5][3] == index) -- clothing stored
    assert(last.payload.appearance.features == nil)           -- features wiped
end
pcall(thread)
assert(posts[#posts].action == 'sync_player_sessions')
synced = posts[#posts].payload.players['7']
assert(synced.appearance.components[5][2] == 9)
assert(synced.appearance.features == nil)
local base = #posts
report(fullComponents({ [5] = { 4, 12, 0 } }), {}, false)
assert(#timers == 1) -- the wipe rides the normal debounced upsert
flushTimers()
assert(#posts == base + 1 and posts[base + 1].action == 'upsert_player_session')
appearance = posts[base + 1].payload.appearance
assert(appearance and appearance.components[5][2] == 12) -- clothing kept
assert(appearance.features == nil)
assert(not serialize(appearance):find('features'))
pcall(thread)
assert(#posts == base + 2 and posts[base + 2].action == 'sync_player_sessions')
synced = posts[base + 2].payload.players['7']
assert(synced.appearance and synced.appearance.components[5][2] == 12)
assert(synced.appearance.features == nil)
assert(not serialize(synced.appearance):find('features'))
report(fullComponents({ [5] = { 4, 13, 0 } }), {}, true)
flushTimers()
assert(#posts == base + 3)
assert(posts[base + 3].payload.appearance.components[5][2] == 13)
assert(posts[base + 3].payload.appearance.features == nil)
report(fullComponents({ [5] = { 4, 9, 0 } }), {}, { 21, 2, 3, 5, 0, 10, 8, 3, 4 })
assert(#timers == 1)
handlers['playerDropped']()
local before = #posts
flushTimers()
assert(#posts == before)
report(fullComponents(), {})
flushTimers()
assert(posts[#posts].action == 'upsert_player_session')
appearance = posts[#posts].payload.appearance
assert(appearance and appearance.features == nil)
assert(not serialize(appearance):find('features'))
