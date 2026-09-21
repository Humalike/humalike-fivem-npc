
unpack = unpack or table.unpack

local handlers, sent, events, timers = {}, {}, {}, {}
local now = 1000
local randomQueue = {}

function RegisterNetEvent() end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerEvent(name, ...) events[#events + 1] = { name, ... } end
function TriggerClientEvent(name, target, npcId, payload)
    sent[#sent + 1] = { name = name, target = target, npc_id = npcId, payload = payload }
end
function GetGameTimer() return now end
function CreateThread() end -- the expiry loop is driven by hand below
function Wait() end
function HumalikeDebug() end
local vmeta = {}
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmeta) end
vmeta.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmeta) end
playerCoords = { x = 0, y = 0, z = 0 }
function DoesEntityExist(entity) return type(entity) == 'number' and entity > 0 end
function GetPlayerPed() return 900 end
orphanModes = {}
function SetEntityOrphanMode(entity, mode) orphanModes[entity] = mode end
function GetEntityCoords(entity)
    if entity == 900 then return vector3(playerCoords.x, playerCoords.y, playerCoords.z) end
    return vector3(0, 0, 0)
end
math.random = function(a, b)
    local value = table.remove(randomQueue, 1)
    assert(value ~= nil, 'random queue exhausted')
    return math.max(a, math.min(b, value))
end

Config = {
    Wounded = {
        Enabled = true,
        DurationMs = 300000,
        DeathChancePercent = 5,
        LingerAfterReviveMs = 30000,
        LingerRadius = 20.0,
        MedicJobs = { 'ambulance', 'ems' },
        PoliceJobs = { 'police' },
        RequireDuty = true,
        ReviveDurationMs = 10000,
        MortuaryDurationMs = 5000,
        TreatmentDistance = 6.0,
    },
}

local jobAnswers = {}
HumalikePlayer = {
    HasJob = function(source, jobNames, requireDuty)
        local answer = jobAnswers[source]
        if not answer then return false end
        if requireDuty and not answer.duty then return false end
        for _, wanted in ipairs(jobNames) do
            for _, held in ipairs(answer.jobs) do
                if held == wanted then return true end
            end
        end
        return false
    end,
}
HumalikeDispatch = {
    Available = function() return false end,
    Report = function() return false end,
}

dofile('server/wounded.lua')

local function lastSent() return sent[#sent] end
AmbientNpcLeases = { [501] = { npc_id = 'npc-1', lease_token = 'tok', network_id = 7701 } }
randomQueue = { 40 }
HumalikeWoundedOnLethalHit('npc-1', 501)
assert(HumalikeWoundedStateOf('npc-1') == 'wounded', 'a common hit wounds')
assert(lastSent().payload.state == 'wounded')
assert(lastSent().payload.network_id == 7701, 'the body carries the lease network id')
assert(lastSent().payload.expires_in_ms == 300000, 'the window is published')
assert(events[#events][1] == 'humalike:npc:npcWounded')
assert(orphanModes[501] == 2, 'the body is kept while nobody is near it')
randomQueue = {}
HumalikeWoundedOnLethalHit('npc-1', 501)
assert(HumalikeWoundedStateOf('npc-1') == 'wounded')
source = 7
jobAnswers[7] = { jobs = { 'mechanic' }, duty = true }
handlers['humalike:npc:finishNpcTreatment']('npc-1', 'revive')
assert(HumalikeWoundedStateOf('npc-1') == 'wounded', 'a mechanic is not a medic')
now = now + 2000
jobAnswers[7] = { jobs = { 'ems' }, duty = false }
handlers['humalike:npc:finishNpcTreatment']('npc-1', 'revive')
assert(HumalikeWoundedStateOf('npc-1') == 'wounded', 'off duty does not count')
now = now + 2000
jobAnswers[7] = { jobs = { 'ems' }, duty = true }
handlers['humalike:npc:finishNpcTreatment']('npc-1', 'revive')
assert(HumalikeWoundedStateOf('npc-1') == nil, 'revived')
assert(orphanModes[501] == 0, 'and released once it is back on its feet')
assert(lastSent().payload.state == 'revived')
assert(lastSent().payload.linger_ms == 30000 and lastSent().payload.linger_radius == 20.0)
assert(events[#events][1] == 'humalike:npc:npcHealed')
randomQueue = { 3 }
HumalikeWoundedOnLethalHit('npc-2', 502)
assert(HumalikeWoundedStateOf('npc-2') == 'deceased')
assert(lastSent().payload.expires_in_ms == nil, 'a body has no countdown')
assert(events[#events][1] == 'humalike:npc:npcDeceased')
now = now + 2000
handlers['humalike:npc:finishNpcTreatment']('npc-2', 'revive')
assert(HumalikeWoundedStateOf('npc-2') == 'deceased', 'the dead are not revived')
now = now + 2000
source = 9
jobAnswers[9] = { jobs = { 'police' }, duty = true }
handlers['humalike:npc:finishNpcTreatment']('npc-2', 'mortuary')
assert(HumalikeWoundedStateOf('npc-2') == nil, 'body cleared')
assert(orphanModes[502] == 0, 'a collected body is released too')
assert(lastSent().payload.state == 'gone')
assert(events[#events][1] == 'humalike:npc:npcDeceased')
randomQueue = { 60 }
HumalikeWoundedOnLethalHit('npc-3', 503)
now = now + 2000
handlers['humalike:npc:finishNpcTreatment']('npc-3', 'revive')
assert(HumalikeWoundedStateOf('npc-3') == 'wounded', 'police do not revive')
now = now + 2000
source = 7
playerCoords = { x = 100, y = 0, z = 0 }
handlers['humalike:npc:finishNpcTreatment']('npc-3', 'revive')
assert(HumalikeWoundedStateOf('npc-3') == 'wounded', 'a medic too far from the body is refused')
playerCoords = { x = 0, y = 0, z = 0 }
now = now + 2000
source = 7
handlers['humalike:npc:finishNpcTreatment']('npc-3', 'revive')
assert(HumalikeWoundedStateOf('npc-3') == nil, 'the medic revived npc-3')
local revivedEvent = nil
for _, event in ipairs(events) do
    if event[1] == 'humalike:npc:npcRevived' then revivedEvent = event end
end
assert(revivedEvent ~= nil, 'the recovery was reported')
assert(revivedEvent[3] == 'npc-3', 'for the NPC that was treated')

randomQueue = { 60 }
HumalikeWoundedOnLethalHit('npc-4', 504)
now = now + 100 -- inside the 1s throttle for this player
handlers['humalike:npc:finishNpcTreatment']('npc-4', 'revive')
assert(HumalikeWoundedStateOf('npc-4') == 'wounded', 'second request inside 1s ignored')
now = now + 300000
HumalikeWoundedSweep()
assert(HumalikeWoundedStateOf('npc-4') == 'deceased', 'bled out, body left behind')
assert(lastSent().payload.state == 'deceased')
assert(lastSent().payload.expires_in_ms == nil, 'a corpse is not waiting for anything')
assert(events[#events][1] == 'humalike:npc:npcDeceased')
assert(events[#events][4] == 'bled_out', 'the reason distinguishes it from a killing')
now = now + 2000
source = 7
handlers['humalike:npc:finishNpcTreatment']('npc-4', 'mortuary')
assert(HumalikeWoundedStateOf('npc-4') == nil, 'the body was collected')
assert(lastSent().payload.state == 'gone')
HumalikeWoundedSweep()
assert(HumalikeWoundedStateOf('npc-4') == nil)
randomQueue = { 60 }
HumalikeWoundedOnLethalHit('npc-5', 505)
now = now + 1000
HumalikeWoundedSweep()
assert(HumalikeWoundedStateOf('npc-5') == 'wounded', 'still within the window')
now = now + 2000
source = 7
sent = {}
handlers['humalike:npc:requestTreatmentRoles']()
assert(lastSent().name == 'humalike:npc:treatmentRoles')
assert(lastSent().npc_id.medic == true and lastSent().npc_id.police == false,
    'an on-duty medic is a medic and not a cop')
sent = {}
handlers['humalike:npc:requestDownedStates']()
local snapshotEntries = 0
for _, message in ipairs(sent) do
    if message.name == 'humalike:npc:npcDownedState' and message.target == 7 then
        snapshotEntries = snapshotEntries + 1
    end
end
assert(snapshotEntries == 1, 'the one still-wounded NPC is replayed to the joiner')
local dispatched = {}
function SetTimeout(delay, fn) timers[#timers + 1] = delay; fn() end
HumalikeDispatch = {}
HumalikeDispatch.Available = function() return true end
HumalikeDispatch.Report = function(kind, payload)
    local coords = payload.coords
    assert(kind == 'npc_medical')
    dispatched[#dispatched + 1] = { coords = coords, kind = payload.status }
end
Config.Wounded.Dispatch = { Enabled = true, Chance = 100, DelayMs = 10000, ThrottleSeconds = 30 }
now = now + 60000
randomQueue = { 60, 50 }
HumalikeWoundedOnLethalHit('npc-7', 507)
assert(#dispatched == 1, 'the ambulance was called')
assert(dispatched[1].kind == 'wounded', 'for someone still alive')
assert(timers[#timers] == 10000, 'after the passer-by delay')

randomQueue = { 3 }
HumalikeWoundedOnLethalHit('npc-8', 508)
assert(#dispatched == 1, 'one scene, one siren')

now = now + 31000
randomQueue = { 3, 50 }
HumalikeWoundedOnLethalHit('npc-9', 509)
assert(#dispatched == 2 and dispatched[2].kind == 'deceased',
    'past the throttle, a killing reports as one')
now = now + 900000
HumalikeWoundedSweep()
assert(HumalikeWoundedStateOf('npc-8') == nil, 'the unclaimed corpse is swept')
assert(HumalikeWoundedStateOf('npc-9') == nil)
Config.Wounded.Dispatch.Chance = 0
now = now + 60000
randomQueue = { 60, 1 }
HumalikeWoundedOnLethalHit('npc-10', 510)
assert(#dispatched == 2, 'an unlucky roll reports nothing')
Config.Wounded.Dispatch.Chance = 100
randomQueue = { 60, 1 }
HumalikeWoundedOnLethalHit('npc-11', 511)
assert(#dispatched == 3, 'and the unreported downing never burned the throttle slot')
now = now + 60000
randomQueue = { 3, 50 }
HumalikeWoundedOnLethalHit('npc-12', 512)
assert(dispatched[#dispatched].kind == 'deceased')
local reportsBefore = #dispatched
now = now + 2000
source = 9
handlers['humalike:npc:finishNpcTreatment']('npc-12', 'mortuary')
assert(HumalikeWoundedStateOf('npc-12') == nil, 'the cop collected the body')
assert(#dispatched == reportsBefore + 1 and dispatched[#dispatched].kind == 'collected',
    'and the collection was reported')

now = now + 60000
randomQueue = { 3, 50 }
HumalikeWoundedOnLethalHit('npc-13', 513)
reportsBefore = #dispatched
now = now + 2000
source = 7
handlers['humalike:npc:finishNpcTreatment']('npc-13', 'mortuary')
assert(HumalikeWoundedStateOf('npc-13') == nil, 'the medic collected the body')
assert(#dispatched == reportsBefore + 1 and dispatched[#dispatched].kind == 'collected',
    'a medic collection is reported the same way')
function GetConvar(_name, default) return default end
dofile('config/convars.lua')
dofile('config/shared.lua')
assert(table.concat(Config.Wounded.MedicJobs, ',') == 'ambulance,ems')
assert(table.concat(Config.Wounded.PoliceJobs, ',') == 'police')
assert(table.concat(HumalikeJobList(' ambulance , ems ,'), ',') == 'ambulance,ems',
    'spacing and trailing separators are tolerated')
assert(#HumalikeJobList('') == 0, 'no jobs configured means the gate lets anyone act')

print('wounded: ok')
