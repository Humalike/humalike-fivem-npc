Config = {
    VehicleDamage = {
        ServerPollIntervalMs = 250,
        ObservationRetentionMs = 60000,
        PendingCandidateMs = 30000,
        UntrustedEventThrottleMs = 100,
        SignificantHealthDrop = 50,
        SevereHealthDrop = 200,
        SevereEngineHealth = 300,
        ServerCooldownMs = 10000,
    },
}

local handlers, posts, timers, threads = {}, {}, {}, {}
local playerPed, playerVehicle = 1, 20
local routingBucket, timer, loaded, nativeSamples = 2, 0, true, 0
local health = {
    [20] = { body = 1000, engine = 1000, networkId = 120 },
    [21] = { body = 1000, engine = 1000, networkId = 120 },
    [22] = { body = 1000, engine = 1000, networkId = 120 },
}
source = 7
HumalikePlayer = { IsCharacterLoaded = function() return loaded end }

function RegisterNetEvent() end
function AddEventHandler(name, fn) handlers[name] = fn end
function CreateThread(fn) threads[#threads + 1] = coroutine.create(fn) end
function Wait(delay)
    assert(delay == 250)
    coroutine.yield()
end
function GetPlayers() return { '7' } end
function GetPlayerPed(playerId) return playerId == 7 and playerPed or 0 end
function DoesEntityExist(entity) return entity == playerPed or health[entity] ~= nil end
function GetVehiclePedIsIn() return playerVehicle end
function GetEntityType(entity) return health[entity] and 2 or 1 end
function NetworkGetNetworkIdFromEntity(entity)
    return health[entity] and health[entity].networkId or 0
end
function GetVehicleBodyHealth(entity)
    nativeSamples = nativeSamples + 1
    return health[entity].body
end
function GetVehicleEngineHealth(entity) return health[entity].engine end
function GetGameTimer() return timer end
function GetPlayerRoutingBucket() return routingBucket end
function SetTimeout(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end
os.date = function(format)
    assert(format == '!%Y-%m-%dT%H:%M:%SZ')
    return '2026-08-22T12:00:00Z'
end
HumalikeHttp = {
    NextSourceEventId = function(playerId) return 'vehicle-event-' .. playerId end,
    PostAction = function(action, payload, callback)
        assert(action == 'ingest_world_event')
        posts[#posts + 1] = payload
        callback(true, 200, { ok = true })
    end,
}

local function resumeSampler()
    local ok, errorMessage = coroutine.resume(threads[1])
    assert(ok, errorMessage)
end

dofile('server/vehicle_damage.lua')
assert(#threads == 1)
resumeSampler() -- initial Wait
local observed = assert(handlers['humalike:npc:vehicleObserved'])
local damaged = assert(handlers['humalike:npc:vehicleDamaged'])
observed(120)
damaged(120)
assert(nativeSamples == 2 and #posts == 0)
for _ = 1, 20 do
    observed(120)
    damaged(120)
end
assert(nativeSamples == 2 and #posts == 0)
timer = 99
observed(120)
damaged(120)
assert(nativeSamples == 2)
timer = 100
observed(120)
damaged(120)
assert(nativeSamples == 4 and #posts == 0, 'both event lanes recover after throttle')
health[20].body = 940
timer = 250
resumeSampler()
assert(#posts == 1 and posts[1].event.severity == 'significant')
resumeSampler()
assert(#posts == 1)
health[20].engine = 500
timer = 500
damaged(120)
assert(#posts == 1)
timer = 10249
resumeSampler()
assert(#posts == 1)
timer = 10250
resumeSampler()
assert(#posts == 2 and posts[2].event.severity == 'severe')
routingBucket = 3
health[20].body, health[20].engine = 1000, 1000
timer = 10350
observed(120)
health[20].body = 940
timer = 10450
damaged(120)
assert(#posts == 3 and posts[3].event.severity == 'significant')
playerVehicle = 21
timer = 10550
observed(120)
health[21].body = 900
timer = 10650
damaged(120)
assert(#posts == 4 and posts[4].event.severity == 'significant')
playerVehicle = 22
timer = 10750
damaged(120, 'severe')
assert(#posts == 4)
playerVehicle = 21
timer = 11000
resumeSampler()
playerVehicle = 22
health[22].body = 900
timer = 11250
resumeSampler()
assert(#posts == 4, 'identity change cleared first-sight pending')
health[22].body = 1000
timer = 11400
observed(120)
damaged(120)
playerVehicle = 0
timer = 11650
resumeSampler()
playerVehicle = 22
health[22].body = 900
timer = 11900
resumeSampler()
assert(#posts == 4, 'exit cleared pending')
health[22].body = 1000
timer = 12100
observed(120)
damaged(120)
timer = 12200
damaged(120)
health[22].body = 900
timer = 42101
resumeSampler()
assert(#posts == 4, 'expired pending did not emit')
health[22].body = 1000
timer = 42500
observed(120)
damaged(120)
local beforeDropSamples = nativeSamples
handlers.playerDropped()
observed(120)
damaged(120)
assert(nativeSamples == beforeDropSamples + 2)
playerVehicle = 0
resumeSampler()
local beforeInvalidSamples = nativeSamples
playerVehicle = 22
observed(121)
damaged(121)
damaged(120.5)
damaged('120')
loaded = false
damaged(120)
loaded = true
assert(nativeSamples == beforeInvalidSamples)
playerVehicle = 20
health[20].body, health[20].engine = 500, 1000
timer = 102501
damaged(120)
assert(#posts == 4)
local attempts = 0
HumalikeHttp.PostAction = function(action, payload, callback)
    assert(action == 'ingest_world_event')
    posts[#posts + 1] = payload
    attempts = attempts + 1
    if attempts == 1 then callback(false, 503, nil)
    else callback(true, 200, { ok = true }) end
end
health[20].body = 400
timer = 102601
damaged(120)
assert(#timers == 1 and timers[1].delay == 1000)
local original = posts[#posts]
timers[1].fn()
assert(posts[#posts] == original and original.event.severity == 'significant')

print('vehicle_damage server: ok')
