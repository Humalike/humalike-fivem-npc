local handlers = {}
local sent = {}
local threads = {}
local timers = {}
local ticks = 0
local waitLimit = 2
local stateNpcId
local networked = false
local healthRestores = 0
local dead = false
LoadedPeds = {}
AmbientNpcEntries = {}
LoadedPeds['static-loop'] = 99

function AddEventHandler(name, handler) handlers[name] = handler end
function CreateThread(handler) threads[#threads + 1] = handler end
function SetTimeout(delay, handler)
    assert(delay == 150)
    timers[#timers + 1] = handler
end
function Wait()
    ticks = ticks + 1
    if ticks > waitLimit then error('done') end
end
function PlayerPedId() return 42 end
local shooting = false
function IsPedShooting(ped) assert(ped == 42) return shooting end
local armed = true
function IsPedArmed() return armed end
local clock = nil
function GetGameTimer() return clock or ticks * 250 end
function PlayerId() return 7 end
local aimedEntity, freeAiming, aimReads = 0, false, 0
function GetEntityPlayerIsFreeAimingAt() aimReads = aimReads + 1 return aimedEntity ~= 0, aimedEntity end
function IsPlayerFreeAiming() return freeAiming end
function IsEntityAPed(entity) return entity ~= 0 end
function Entity() return { state = { humalike_npc_id = stateNpcId } } end
function DoesEntityExist() return true end
function NetworkGetEntityIsNetworked() return networked end
function NetworkGetNetworkIdFromEntity() return 55 end
function IsEntityDead() return dead end
function IsPedDeadOrDying() return dead end
function GetEntityMaxHealth() return 1000000 end
function SetEntityHealth(_, health)
    assert(health == 1000000)
    healthRestores = healthRestores + 1
end
function HumalikeDebug() end
function GetPedLastDamageBone() return true, 31086 end
function TriggerServerEvent(...)
    sent[#sent + 1] = { ... }
end

dofile('../world/client/pulse.lua')
dofile('client/combat.lua')
assert(#threads == 2, 'the shared pulse and the health loop: the gun has no thread of its own')
pcall(threads[2])
assert(handlers.entityDamaged)
assert(healthRestores == 2)

clock = 1000
shooting = true
assert(HumalikePulse.Run(clock) == 100 and #threads == 3, 'armed: the frame thread is started')
assert(#sent == 1 and sent[1][1] == 'humalike:npc:gunshotFired', 'a shot on the frame the gun is first seen is not lost')
local frameWaits = {}
function Wait(ms) frameWaits[#frameWaits + 1] = ms coroutine.yield() end
local frames = coroutine.create(threads[3])
local function frame(at, firing)
    clock, shooting = at, firing
    assert(coroutine.resume(frames))
end
frame(1016, true)
frame(1033, true)
assert(#sent == 1 and sent[1][1] == 'humalike:npc:gunshotFired', 'automatic fire reports once per burst')
frame(1300, false)
assert(#sent == 1)
frame(1540, false) -- 507 ms of silence closes the burst
frame(1556, true)
assert(#sent == 2 and sent[2][1] == 'humalike:npc:gunshotFired', 'and rearms after 500 ms of silence')
assert(frameWaits[#frameWaits] == 0, 'one look per frame while a gun is out')
table.remove(sent, 2) -- preserve the existing event index assertions below
armed = false
clock = 1600
HumalikePulse.Run(clock)
frame(1616, false)
assert(coroutine.status(frames) == 'suspended', 'an open burst is watched to its end')
frame(2100, false)
assert(coroutine.status(frames) == 'suspended')
local shootingChecks = 0
function IsPedShooting() shootingChecks = shootingChecks + 1 return false end
assert(coroutine.resume(frames))
assert(coroutine.status(frames) == 'dead' and shootingChecks == 0, 'holstered, nobody asks about shots')
clock = 2200
assert(HumalikePulse.Run(clock) == 100 and #threads == 3, 'and the pulse looks at the hand every 100 ms')

assert(aimReads == 0)
freeAiming, aimedEntity, stateNpcId = true, 77, 'ambient-aim'
AmbientNpcEntries['ambient-aim'] = { entity_id = 707 }
clock = 2300
assert(HumalikePulse.Run(clock) == 50, 'aiming at an NPC: the next look comes 50 ms later')
assert(sent[#sent][1] == 'humalike:npc:aimingCandidateChanged' and sent[#sent][2] == 'ambient-aim'
    and sent[#sent][3] == 707)
local aimEvents = #sent
clock = 2350
HumalikePulse.Run(clock)
assert(#sent == aimEvents, 'the same target is not announced twice')
freeAiming = false
clock = 2400
assert(HumalikePulse.Run(clock) == 100 and sent[#sent][1] == 'humalike:npc:aimingCandidateChanged'
    and sent[#sent][2] == nil, 'lowering the gun clears the candidate')
table.remove(sent)
table.remove(sent)
stateNpcId, AmbientNpcEntries['ambient-aim'] = nil, nil
clock = nil

local damageNotes = {}
HumalikeNpcShove = { NoteDamage = function(ped, at) damageNotes[#damageNotes + 1] = { ped, at } end }
stateNpcId = 'static-1'
LoadedPeds['static-1'] = 100
handlers.entityDamaged(100, 42, 0, 6)
assert(healthRestores == 3)
assert(#damageNotes == 1 and damageNotes[1][1] == 100 and damageNotes[1][2] == GetGameTimer(),
    'every hit the player lands is stamped for the shove detector')
assert(sent[2][1] == 'humalike:npc:npcDamaged')
assert(sent[2][2] == 'static-1' and sent[2][3] == -1)
assert(sent[3][1] == 'humalike:npc:npcAttacked')
assert(sent[3][2] == 'static-1' and sent[3][3] == nil)
assert(sent[3][4] == 0 and sent[3][5] == 6) -- melee

stateNpcId = 'ambient-1'
AmbientNpcEntries['ambient-1'] = { entity_id = 101 }
dead = false
handlers.entityDamaged(101, 42, 10, 25)
handlers.entityDamaged(101, 42, 10, 25)
assert(healthRestores == 3)
assert(sent[4][1] == 'humalike:npc:npcDamaged')
assert(sent[4][2] == 'ambient-1' and sent[4][3] == 101)
assert(sent[4][4] == 31086 and sent[4][5] == 10 and sent[4][6] == 25)
assert(sent[5][1] == 'humalike:npc:npcAttacked')
assert(sent[5][2] == 'ambient-1' and sent[5][3] == 101)
assert(sent[5][4] == 10 and sent[5][5] == 25) -- firearm
assert(#timers == 1 and #sent == 7) -- repeated damage shares one death check
dead = true -- FiveM marks the ped dead after entityDamaged returns
timers[1]()
assert(#sent == 8 and sent[8][1] == 'humalike:npc:npcDied')
assert(sent[8][2] == 'ambient-1' and sent[8][3] == 101)
for _, e in ipairs(sent) do
    assert(e[1] ~= 'humalike:npc:npcLethalHit', 'no unauthenticated lethal-hit event')
end

handlers.entityDamaged(101, 99, 10, 25)
stateNpcId = nil
handlers.entityDamaged(101, 42, 10, 25)
assert(#sent == 8)

local persistentServer = assert(io.open('server/persistent.lua')):read('*a')
assert(not persistentServer:find('SetEntityInvincible'))
assert(not persistentServer:find('SetEntityCanBeDamaged'))
assert(not persistentServer:find('SetEntityMaxHealth'))

local persistentClient = assert(io.open('client/persistent_control.lua')):read('*a')
local persistentBindings = assert(io.open('client/main.lua')):read('*a')
assert(persistentClient:find('SetEntityInvincible%(ped, false%)'))
assert(persistentClient:find('SetEntityCanBeDamaged%(ped, true%)'))
assert(persistentClient:find('SetEntityMaxHealth%(ped, 1000000%)'))
assert(persistentClient:find('SetPedSuffersCriticalHits%(ped, false%)'))
assert(persistentClient:find('SetPedDiesWhenInjured%(ped, false%)'))
assert(persistentClient:find('NetworkHasControlOfEntity%(ped%)'))
assert(persistentClient:find('FreezeEntityPosition%(ped, true%)'))
assert(not persistentClient:find('reporter == localServerId'))
local _, freezeCalls = persistentClient:gsub('FreezeEntityPosition%(ped, true%)', '')
assert(freezeCalls >= 2)
assert(persistentClient:find('SetEntityCoordsNoOffset'))
assert(persistentBindings:find('StopPedSpeaking%(ped, true%)'))
assert(persistentBindings:find('DisablePedPainAudio%(ped, true%)'))
