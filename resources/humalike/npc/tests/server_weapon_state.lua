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

Config = { DefaultVoiceDistance = 15 }
NpcRegistry = { ['npc-1'] = { x = 10, y = 0, z = 0, voice_distance = 12 } }
AmbientNpcLeases = {
    [55] = { npc_id = 'ambient-1', lease_token = 'ambient-lease' },
}
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
function GetPlayerRoutingBucket() return 3 end
function GetEntityHealth() return entityHealth end
function GetEntityCoords() return { x = 0, y = 0, z = 0 } end
function DoesEntityExist(entity) return entity == 42 or entity == 55 end
function GetEntityRoutingBucket() return 3 end
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

handlers['humalike:npc:npcDied']('ambient-1', 55)
assert(#observations == 21 and observations[21].event.type == 'npc_died')
assert(observations[21].event.fatal == false, 'a wounding by default')
assert(observations[21].event.npc_id == 'ambient-1')
assert(observations[21].event.lease_token == 'ambient-lease')
handlers['humalike:npc:npcDied']('ambient-1', 55)
assert(#observations == 21)
handlers['humalike:npc:npcRevived']('7', 'ambient-1', 55, 'ambient-lease')
assert(#observations == 22 and observations[22].event.type == 'npc_revived')
assert(observations[22].event.npc_id == 'ambient-1')
assert(observations[22].event.lease_token == 'ambient-lease')
entityHealth = 100
handlers['humalike:npc:npcDied']('ambient-1', 55)
assert(#observations == 22)

failures = 0
local aiming = handlers['humalike:npc:aimingCandidateChanged']
aiming('npc-1', nil)
assert(#observations == 22 and #timers == 1 and timers[1].delay == 150)
aiming('npc-1', nil) -- duplicate candidate does not restart the debounce
assert(#timers == 1)
runTimer()
assert(#observations == 23 and observations[23].event.type == 'aiming_started')
assert(observations[23].event.npc_id == 'npc-1')

aiming(nil, nil)
aiming('npc-1', nil)
assert(#timers == 2)
runTimer() -- stale stop after a short loss of aim
runTimer() -- same stable target
assert(#observations == 23)

aiming('ambient-1', 55)
runTimer()
assert(#observations == 25)
assert(observations[24].event.type == 'aiming_stopped')
assert(observations[24].event.npc_id == 'npc-1')
assert(observations[25].event.type == 'aiming_started')
assert(observations[25].event.npc_id == 'ambient-1')
assert(observations[25].event.lease_token == 'ambient-lease')

aiming(nil, nil)
assert(timers[1].delay == 250)
runTimer()
assert(#observations == 26 and observations[26].event.type == 'aiming_stopped')
assert(observations[26].event.npc_id == 'ambient-1')
assert(observations[26].event.lease_token == 'ambient-lease')
aiming('missing', nil)
aiming('ambient-1', 56)
assert(#observations == 26 and #timers == 0)

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

print('server_weapon_state (deaths): ok')
