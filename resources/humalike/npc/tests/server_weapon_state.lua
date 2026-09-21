local handlers = {}
local observations = {}
local retries = 0
local failures = 1
local gameTimer = 100
local stateBagHandler
local entityHealth = 0
local timers = {}
local retryDelays = {}
local hashes = { WEAPON_UNARMED = 0, WEAPON_PISTOL = 10, WEAPON_CARBINERIFLE = 20 }

function GetConvar(_name, default) return default end
dofile('config/shared.lua')
NpcRegistry = { ['npc-1'] = { x = 10, y = 0, z = 0, voice_distance = 12 } }
AmbientNpcLeases = {
    [55] = { npc_id = 'ambient-1', lease_token = 'ambient-lease' },
}
local coords = { [42] = { x = 8, y = 0, z = 0 }, [55] = { x = 10, y = 0, z = 0 } }
local existing = { [42] = true, [55] = true }
local buckets = {}
local characterLoaded = true
HumalikePlayer = { IsCharacterLoaded = function() return characterLoaded end }
local exported = {}
exports = function(name, callback) exported[name] = callback end

source = 7

os.time = function() return 1234 end
os.date = function(format)
    assert(format == '!%Y-%m-%dT%H:%M:%SZ')
    return '2026-08-05T12:34:56Z'
end

function GetHashKey(name) return hashes[name] or 999 end
function GetPlayerPed() return 42 end
local selectedWeapon = 10
function GetSelectedPedWeapon() return selectedWeapon end
local playerBucket = 0
function GetPlayerRoutingBucket() return playerBucket end
function GetEntityHealth() return entityHealth end
-- Server-side GetEntityCoords returns a vector3 userdata, never a Lua table;
-- model it with a non-table value so reach checks cannot rely on type()=='table'.
local vectorMeta = { __index = function(self, key) return rawget(self, '_' .. key) end }
local function vec3(c)
    local v = setmetatable({}, vectorMeta)
    rawset(v, '_x', c.x); rawset(v, '_y', c.y); rawset(v, '_z', c.z)
    return v
end
-- and make type() report it the way FiveM does for vector3 values.
local rawType = type
type = function(value)
    if getmetatable(value) == vectorMeta then return 'vector3' end
    return rawType(value)
end
function GetEntityCoords(entity) return vec3(coords[entity] or { x = 0, y = 0, z = 0 }) end
function DoesEntityExist(entity) return existing[entity] == true end
function GetEntityRoutingBucket(entity) return buckets[entity] or 0 end
function GetGameTimer() return gameTimer end
function GetResourceState() return 'started' end
function GetPlayers() return { '7' } end
function Player() return { state = {} } end
function GetPlayerFromStateBagName(name)
    return tonumber(name:match('^player:(%d+)$')) or 0
end
function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
function AddStateBagChangeHandler(key, bag, handler)
    assert(key == 'HandsUp' and bag == nil)
    stateBagHandler = handler
end
function TriggerEvent(name, ...)
    handlers[name](...)
end
function SetTimeout(delay, callback)
    if delay == 1000 or delay == 2000 or delay == 4000 or delay == 8000 then
        retries = retries + 1
        retryDelays[#retryDelays + 1] = delay
        callback()
    else
        assert(delay == 150 or delay == 250)
        timers[#timers + 1] = { delay = delay, callback = callback }
    end
end

local function runTimer(index)
    local timer = table.remove(timers, index or 1)
    assert(timer)
    timer.callback()
end

HumalikeHttp = {
    NextSourceEventId = function(playerId) return ('event-%d-1'):format(playerId) end,
    PostAction = function(action, observation, callback)
        assert(action == 'ingest_world_event')
        observations[#observations + 1] = observation
        if failures > 0 then
            failures = failures - 1
            callback(false, 503, nil)
        else
            callback(true, 200, { ok = true })
        end
    end,
}

dofile('../server/core/text.lua')
dofile('server/world_events.lua')
dofile('server/weapon_state.lua')

local handle = handlers['humalike:npc:weaponStateChanged']
handle('weapon_drawn', 0, 10, 'WEAPON_UNARMED', 'WEAPON_PISTOL')
assert(retries == 1 and observations[1] == observations[2])
assert(observations[1].source_event_id == observations[2].source_event_id)
assert(observations[1].fivem_session_id == 7)
assert(observations[1].occurred_at == '2026-08-05T12:34:56Z')
assert(observations[1].event.type == 'weapon_drawn')
assert(observations[1].event.weapon == 'WEAPON_PISTOL')

handle('weapon_holstered', 20, 0, 'WEAPON_CARBINERIFLE', 'WEAPON_UNARMED')
assert(observations[3].event.type == 'weapon_holstered')
assert(observations[3].event.weapon == 'WEAPON_CARBINERIFLE')

handle('weapon_drawn', 20, 10, 'WEAPON_CARBINERIFLE', 'WEAPON_PISTOL')
handle('unknown', 0, 10, 'WEAPON_UNARMED', 'WEAPON_PISTOL')
handle('weapon_drawn', 0, 10, 'WEAPON_UNARMED', 'WEAPON_FAKE')
assert(#observations == 3)

failures = 1
handlers['humalike:npc:gunshotFired']()
assert(#observations == 5 and observations[4] == observations[5])
assert(observations[4].source_event_id == observations[5].source_event_id)
assert(observations[4].fivem_session_id == 7)
assert(observations[4].event.type == 'gunshot_fired')

gameTimer = 110
handlers['humalike:npc:gunshotFired']()
assert(#observations == 5)

NpcRegistry = {}
gameTimer = 125
handlers['humalike:npc:gunshotFired']()
assert(#observations == 6 and observations[6].event.type == 'gunshot_fired')
NpcRegistry['npc-1'] = { x = 10, y = 0, z = 0, voice_distance = 12 }

local identity = { type = 'identity_document_shown', full_name = 'Jan Kowalski', sex = 'M',
    ssn = '12345678901', issued_at = '2026-08-05', last_name = 'Kowalski' }
exported.ReportPlayerEvent(7, identity)
assert(observations[7].event.type == 'identity_document_shown')
assert(observations[7].event.full_name == 'Jan Kowalski')
assert(observations[7].event.sex == 'M' and observations[7].event.ssn == '12345678901')
assert(observations[7].event.issued_at == '2026-08-05')
assert(observations[7].event.last_name == 'Kowalski')
exported.ReportPlayerEvent(7, { type = 'police_badge_shown' })
assert(observations[8].event.type == 'police_badge_shown')
exported.ReportPlayerEvent(7, { type = 'item_dropped', item_name = 'water', quantity = 2 })
assert(observations[9].event.type == 'item_dropped')
assert(observations[9].event.item_name == 'water' and observations[9].event.quantity == 2)
exported.ReportPlayerEvent(7, { type = 'item_picked_up', item_name = 'bread', quantity = 1 })
assert(observations[10].event.type == 'item_picked_up')

exported.ReportPlayerEvent(7, { type = 'item_given', item_name = 'water', quantity = 1 })
exported.ReportPlayerEvent(7, { type = 'item_dropped', item_name = '../water', quantity = 1 })
exported.ReportPlayerEvent(7, { type = 'item_dropped', item_name = 'water', quantity = 0 })
exported.ReportPlayerEvent(7, nil)
local invalidIdentity = { type = 'identity_document_shown', full_name = '', sex = 'M',
    ssn = '12345678901', issued_at = '2026-08-05', last_name = 'Kowalski' }
exported.ReportPlayerEvent(7, invalidIdentity)
exported.ReportPlayerEvent(0, identity)
characterLoaded = false
exported.ReportPlayerEvent(7, identity)
characterLoaded = true
assert(#observations == 10)

handlers.explosionEvent('7', { explosionType = 2, posX = 100, posY = 2, posZ = 3 })
assert(observations[11].event.type == 'explosion_occurred')
assert(observations[11].event.explosion_type == 2)
assert(observations[11].event.x == 100 and observations[11].event.y == 2
    and observations[11].event.z == 3)
handlers.explosionEvent(7, { explosionType = '2', posX = 0, posY = 0, posZ = 0 })
assert(#observations == 11)

assert(stateBagHandler and #observations == 11)
handlers.playerJoining()
failures = 1
stateBagHandler('player:7', 'HandsUp', true)
assert(#observations == 13 and observations[12] == observations[13])
assert(observations[12].source_event_id == observations[13].source_event_id)
assert(observations[12].fivem_session_id == 7)
assert(observations[12].event.type == 'hands_raised')
stateBagHandler('player:7', 'HandsUp', true)
assert(#observations == 13)
stateBagHandler('player:7', 'HandsUp', nil)
assert(#observations == 14 and observations[14].event.type == 'hands_lowered')
stateBagHandler('player:7', 'HandsUp', false)
assert(#observations == 14)

exported.ReportPlayerEvent(7, { type = 'ems_badge_shown' })
assert(observations[15].event.type == 'ems_badge_shown')
exported.ReportPlayerEvent(7, { type = 'doj_badge_shown' })
assert(observations[16].event.type == 'doj_badge_shown')

failures = 1
handlers['humalike:npc:npcAttacked']('npc-1', nil, 10, 4, 'WEAPON_PISTOL')
assert(#observations == 18 and observations[17] == observations[18])
assert(observations[17].source_event_id == observations[18].source_event_id)
assert(observations[17].fivem_session_id == 7)
assert(observations[17].occurred_at == '2026-08-05T12:34:56Z')
assert(observations[17].event.type == 'attacked_npc')
assert(observations[17].event.npc_id == 'npc-1')
assert(observations[17].event.weapon == 'WEAPON_PISTOL')
assert(observations[17].event.damage == 4)
handlers['humalike:npc:npcAttacked']('missing', nil, 10, 4, 'WEAPON_PISTOL')
handlers['humalike:npc:npcAttacked']('npc-1', nil, 10, 4, 'WEAPON_FAKE')
handlers['humalike:npc:npcAttacked']('npc-1', nil, 10, -1, 'WEAPON_PISTOL')
handlers['humalike:npc:npcAttacked']('npc-1', nil, '10', 4, 'WEAPON_PISTOL')
assert(#observations == 18)
selectedWeapon = 0
handlers['humalike:npc:npcAttacked']('npc-1', nil, 0, 2, 'WEAPON_UNARMED')
assert(#observations == 19 and observations[19].event.weapon == 'WEAPON_UNARMED')
handlers['humalike:npc:npcAttacked']('npc-1', nil, 10, 2, 'WEAPON_PISTOL')
assert(#observations == 19)
characterLoaded = false
handlers['humalike:npc:npcAttacked']('npc-1', nil, 0, 2, 'WEAPON_UNARMED')
characterLoaded = true
selectedWeapon = 10
handlers['humalike:npc:npcAttacked']('npc-1', nil, 0, 2, 'WEAPON_UNARMED')
assert(#observations == 19)

selectedWeapon = 0
handlers['humalike:npc:npcAttacked']('ambient-1', 55, 0, 3, 'WEAPON_UNARMED')
assert(#observations == 20 and observations[20].event.npc_id == 'ambient-1')
assert(observations[20].event.weapon == 'WEAPON_UNARMED')
assert(observations[20].event.lease_token == 'ambient-lease')
handlers['humalike:npc:npcAttacked']('ambient-1', 56, 0, 3, 'WEAPON_UNARMED')
handlers['humalike:npc:npcAttacked']('wrong-npc', 55, 0, 3, 'WEAPON_UNARMED')
assert(#observations == 20)
coords[42] = { x = 20, y = 0, z = 0 }
handlers['humalike:npc:npcAttacked']('ambient-1', 55, 0, 3, 'WEAPON_UNARMED')
handlers['humalike:npc:npcAttacked']('npc-1', nil, 0, 3, 'WEAPON_UNARMED')
assert(#observations == 20, 'a punch from ten metres away never landed')
selectedWeapon = 10
handlers['humalike:npc:npcAttacked']('ambient-1', 55, 10, 3, 'WEAPON_PISTOL')
assert(#observations == 21, 'a shot carries across the street')
coords[42] = { x = 200, y = 0, z = 0 }
handlers['humalike:npc:npcAttacked']('ambient-1', 55, 10, 3, 'WEAPON_PISTOL')
assert(#observations == 21, 'but not from another district')
coords[42] = { x = 8, y = 0, z = 0 }
selectedWeapon = 0

handlers['humalike:npc:npcDied']('ambient-1', 55)
assert(#observations == 22 and observations[22].event.type == 'npc_died')
assert(observations[22].event.fatal == false, 'a wounding by default')
assert(observations[22].event.npc_id == 'ambient-1')
assert(observations[22].event.lease_token == 'ambient-lease')
handlers['humalike:npc:npcDied']('ambient-1', 55)
assert(#observations == 22)
handlers['humalike:npc:npcRevived']('7', 'ambient-1', 55, 'ambient-lease')
assert(#observations == 23 and observations[23].event.type == 'npc_revived')
assert(observations[23].event.npc_id == 'ambient-1')
assert(observations[23].event.lease_token == 'ambient-lease')
entityHealth = 100
handlers['humalike:npc:npcDied']('ambient-1', 55)
assert(#observations == 23)

failures = 0
local aiming = handlers['humalike:npc:aimingCandidateChanged']
aiming('npc-1', nil)
assert(#observations == 23 and #timers == 1 and timers[1].delay == 150)
aiming('npc-1', nil) -- duplicate candidate does not restart the debounce
assert(#timers == 1)
runTimer()
assert(#observations == 24 and observations[24].event.type == 'aiming_started')
assert(observations[24].event.npc_id == 'npc-1')

aiming(nil, nil)
aiming('npc-1', nil)
assert(#timers == 2)
runTimer() -- stale stop after a short loss of aim
runTimer() -- same stable target
assert(#observations == 24)

aiming('ambient-1', 55)
runTimer()
assert(#observations == 26)
assert(observations[25].event.type == 'aiming_stopped')
assert(observations[25].event.npc_id == 'npc-1')
assert(observations[26].event.type == 'aiming_started')
assert(observations[26].event.npc_id == 'ambient-1')
assert(observations[26].event.lease_token == 'ambient-lease')

aiming(nil, nil)
assert(timers[1].delay == 250)
runTimer()
assert(#observations == 27 and observations[27].event.type == 'aiming_stopped')
assert(observations[27].event.npc_id == 'ambient-1')
assert(observations[27].event.lease_token == 'ambient-lease')
aiming('missing', nil)
aiming('ambient-1', 56)
assert(#observations == 27 and #timers == 0)

local before = #observations
local beforeRetries = retries
failures = 10
handle('weapon_drawn', 0, 10, 'WEAPON_UNARMED', 'WEAPON_PISTOL')
assert(#observations == before + 5)
assert(retries == beforeRetries + 4)
assert(retryDelays[#retryDelays - 3] == 1000 and retryDelays[#retryDelays - 2] == 2000
    and retryDelays[#retryDelays - 1] == 4000 and retryDelays[#retryDelays] == 8000)
for index = before + 2, #observations do
    assert(observations[index] == observations[before + 1])
    assert(observations[index].source_event_id == observations[before + 1].source_event_id)
end

before = #observations
beforeRetries = retries
failures = 1
HumalikeHttp.PostAction = function(action, observation, callback)
    assert(action == 'ingest_world_event')
    observations[#observations + 1] = observation
    callback(false, 422, nil)
end
handle('weapon_drawn', 0, 10, 'WEAPON_UNARMED', 'WEAPON_PISTOL')
assert(#observations == before + 1 and retries == beforeRetries)
entityHealth = 0
handlers['humalike:npc:npcRevived']('7', 'ambient-1', 55, 'ambient-lease')
local beforeKilling = #observations
HumalikeWoundedStateOf = function() return 'deceased' end
handlers['humalike:npc:npcDied']('ambient-1', 55)
assert(#observations == beforeKilling + 1, 'the death was reported')
assert(observations[#observations].event.fatal == true, 'a killing says so')
HumalikeWoundedStateOf = nil


HumalikeHttp.PostAction = function(action, observation, callback)
    assert(action == 'ingest_world_event')
    observations[#observations + 1] = observation
    callback(true, 200, { ok = true })
end
local shoved = handlers['humalike:npc:npcShoved']
gameTimer = 10000
local beforeShove = #observations
shoved('npc-1', nil, 'bump')
assert(#observations == beforeShove + 1, 'a shove reaches the edge')
assert(observations[#observations].event.type == 'shoved_npc')
assert(observations[#observations].event.npc_id == 'npc-1')
assert(observations[#observations].event.intensity == 'bump')
assert(observations[#observations].event.lease_token == nil)
assert(observations[#observations].fivem_session_id == 7)
shoved('npc-1', nil, 'knocked_down')
assert(#observations == beforeShove + 1, 'the same player and npc are rate-limited server-side')
gameTimer = 12000
shoved('npc-1', nil, 'knocked_down')
assert(#observations == beforeShove + 2, 'after the gap a new report goes through')
assert(observations[#observations].event.intensity == 'knocked_down')
shoved('ambient-1', 55, 'bump')
assert(#observations == beforeShove + 3, 'another npc has its own clock')
assert(observations[#observations].event.npc_id == 'ambient-1')
assert(observations[#observations].event.lease_token == 'ambient-lease')
gameTimer = 20000
shoved('ambient-1', 56, 'bump')
shoved('wrong-npc', 55, 'bump')
shoved('npc-1', 55, 'bump')
shoved('npc-1', nil, 'tickle')
shoved('npc-1', nil, nil)
shoved(7, nil, 'bump')
characterLoaded = false
shoved('npc-1', nil, 'bump')
characterLoaded = true
assert(#observations == beforeShove + 3,
    'unknown targets, intensities and unloaded players are dropped')
handlers.playerDropped()
shoved('npc-1', nil, 'bump')
assert(#observations == beforeShove + 4, 'a dropped player starts with a clean clock')

gameTimer = 30000
coords[42] = { x = 20, y = 0, z = 0 }
shoved('ambient-1', 55, 'bump')
shoved('npc-1', nil, 'bump')
assert(#observations == beforeShove + 4, 'a target ten metres away in the same bucket is not a shove')
coords[42] = { x = 8, y = 0, z = 0 }
PersistentNpcEntities = { ['npc-1'] = 77 }
existing[77] = true
coords[77] = { x = 9, y = 0, z = 0 }
buckets[77] = 4
shoved('npc-1', nil, 'bump')
assert(#observations == beforeShove + 4, 'a static NPC standing in another bucket is not a shove')
buckets[77] = 0
shoved('npc-1', nil, 'bump')
assert(#observations == beforeShove + 5, 'the resolved static entity is checked, not the definition')
PersistentNpcEntities = nil
gameTimer = 35000
playerBucket = 2
shoved('npc-1', nil, 'bump')
assert(#observations == beforeShove + 5,
    'a static definition without an entity stands in bucket 0')
playerBucket = 0
shoved('npc-1', nil, 'bump')
assert(#observations == beforeShove + 6)

local limit, window = Config.Shove.MaxReportsPerWindow, Config.Shove.ReportWindowMs
gameTimer = gameTimer + window + Config.Shove.ServerGapMs
for index = 1, limit + 1 do
    AmbientNpcLeases[60 + index] = { npc_id = 'cap-' .. index, lease_token = 'lease-' .. index }
    existing[60 + index] = true
    coords[60 + index] = { x = 9, y = 0, z = 0 }
end
local capBefore = #observations
for index = 1, limit + 1 do shoved('cap-' .. index, 60 + index, 'bump') end
assert(#observations == capBefore + limit, 'a player reports at most MaxReportsPerWindow shoves per window')
gameTimer = gameTimer + window
shoved('cap-' .. (limit + 1), 60 + limit + 1, 'bump')
assert(#observations == capBefore + limit + 1, 'the window slides')
handlers.playerDropped()
shoved('cap-1', 61, 'bump')
assert(#observations == capBefore + limit + 2, 'a dropped player starts with a clean window and clocks')

print('server_weapon_state (deaths): ok')
