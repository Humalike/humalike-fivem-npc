
local calls = {}
local threads = {}
local coordsByEntity = {}
local dead = true
local playingAnim = false
local hasControl = true
local activePlayers = {}

local function record(name, ...) calls[#calls + 1] = { name = name, ... } end
local function names()
    local list = {}
    for index, call in ipairs(calls) do list[index] = call.name end
    return table.concat(list, ',')
end
local function indexOf(name)
    for index, call in ipairs(calls) do
        if call.name == name then return index end
    end
    return nil
end
local function countOf(name)
    local total = 0
    for _, call in ipairs(calls) do
        if call.name == name then total = total + 1 end
    end
    return total
end

local vectorMeta = {}
vectorMeta.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta)
end
vectorMeta.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end

local handlers = {}
function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
function TriggerEvent(name, ...) record('TriggerEvent:' .. name, ...) end
function TriggerServerEvent(name, ...) record('TriggerServerEvent:' .. name, ...) end
function CreateThread(callback) threads[#threads + 1] = callback end
waitBudget = 0
local waits = 0
function Wait()
    waits = waits + 1
    if waits > waitBudget then error('stop thread', 0) end
end
local function runThread(thread, iterations)
    waits, waitBudget = 0, iterations
    pcall(thread)
    waitBudget = 0
end
function GetGameTimer() return 1000 end
function DoesEntityExist(entity) return entity ~= nil and entity ~= 0 end
function IsEntityDead() return dead end
function IsPedDeadOrDying() return dead end
function ResurrectPed() record('ResurrectPed'); dead = false end
function ClearPedBloodDamage() record('ClearPedBloodDamage') end
function GetEntityMaxHealth() return 200 end
function GetEntityHealth() return 200 end
function SetEntityHealth() record('SetEntityHealth') end
function SetEntityInvincible(_, on) record('SetEntityInvincible', on) end
function SetPedCanRagdoll() end
function SetPedCanRagdollFromPlayerImpact(_, on) record('NoImpactRagdoll', on) end
function SetPedRagdollOnCollision(_, on) record('NoCollisionRagdoll', on) end
function SetPedDiesInWater() end
function SetPedKeepTask() end
function SetPedToRagdoll() record('SetPedToRagdoll') end
function SetBlockingOfNonTemporaryEvents(_, blocked) record('Blocking', blocked) end
function FreezeEntityPosition(_, frozen) record('Freeze', frozen) end
function ClearPedTasksImmediately() record('ClearPedTasksImmediately') end
function ClearPedTasks() record('ClearPedTasks') end
function TaskStandStill(_, duration) record('TaskStandStill', duration) end
function TaskWanderStandard() record('TaskWanderStandard') end
function TaskPlayAnim(_, dict, clip) record('TaskPlayAnim', dict, clip); playingAnim = true end
function IsEntityPlayingAnim() return playingAnim end
function IsPedRagdoll() return false end
function HasAnimDictLoaded() return true end
function RequestAnimDict(dict) record('RequestAnimDict', dict) end
function NetworkHasControlOfEntity() return hasControl end
function GetEntityCoords(entity) return coordsByEntity[entity] or vector3(0, 0, 0) end
function GetActivePlayers() return activePlayers end
function GetPlayerPed(playerId) return playerId end
function PlayerPedId() return 99 end
function HumalikeInteractionProgress() return true end
function SetEntityCanBeDamaged() record('SetEntityCanBeDamaged') end
function SetPedSuffersCriticalHits(_, on) record('SetPedSuffersCriticalHits', on) end
function SetEntityAsMissionEntity() record('SetEntityAsMissionEntity') end
function SetPedAsNoLongerNeeded() record('SetPedAsNoLongerNeeded') end
function DeleteEntity() record('DeleteEntity') end
function ReleaseActionControl() record('ReleaseActionControl') end
function NetworkIsSessionStarted() return true end
networkedPeds = {}
function NetworkDoesEntityExistWithNetworkId(id) return networkedPeds[id] ~= nil end
function NetworkGetEntityFromNetworkId(id) return networkedPeds[id] end

Config = {
    Wounded = { Enabled = true, LingerRadius = 20.0 },
    AmbientControl = { InteractionDistance = 3.0 },
}
LoadedPeds = { ['npc-1'] = 42 }
AmbientPeds = {}

dofile('client/wounded.lua')
assert(#threads >= 2, 'a preload thread and the pose watchdog')
threads[1]()
assert(countOf('RequestAnimDict') == 2, 'both the pose dict and its fallback')

calls = {}
handlers['humalike:npc:npcDownedState']('npc-1', { state = 'wounded' })
assert(indexOf('ResurrectPed'), 'a dead ped is resurrected: ' .. names())
assert(indexOf('ResurrectPed') < indexOf('SetEntityHealth'), 'resurrect, then heal')
assert(indexOf('ResurrectPed') < indexOf('TaskPlayAnim'), 'resurrect, then pose')
assert(indexOf('Freeze') < indexOf('TaskPlayAnim'), 'frozen before the pose: ' .. names())
assert(indexOf('ReleaseActionControl'), 'the held deed ends: ' .. names())
assert(indexOf('NoImpactRagdoll'), 'a shove does not move it: ' .. names())
assert(indexOf('SetEntityAsMissionEntity'), 'the body is kept from the population sweep: ' .. names())

assert(indexOf('ReleaseActionControl') < indexOf('TaskPlayAnim'), 'and ends before the pose')
assert(HumalikeDownedState('npc-1') == 'wounded')
assert(indexOf('TriggerServerEvent:humalike:npc:requestTreatmentRoles'),
    'the job roles are requested on a downing: ' .. names())
local watchdog = threads[2]
hasControl = false
runThread(watchdog, 1)
hasControl = true
calls = {}
runThread(watchdog, 1)
assert(indexOf('Blocking'), 'the flags are re-asserted, not trusted: ' .. names())
assert(indexOf('SetEntityAsMissionEntity'), 'so is the keep-alive, on the new owner: ' .. names())
assert(indexOf('NoImpactRagdoll'), 'including the ones a new owner never set')
assert(indexOf('TaskPlayAnim'), 'and the pose is put back on taking ownership')
local options = HumalikeTreatmentOptions('npc-1')
assert(#options == 0, 'no medical options before the server has answered')

handlers['humalike:npc:treatmentRoles']({ medic = true, police = false })
assert(indexOf('TriggerEvent:humalike:npc:treatmentAccessChanged'),
    'a role change tells the wheels to rebuild: ' .. names())
options = HumalikeTreatmentOptions('npc-1')
assert(#options == 1 and options[1].text == 'Revive',
    'a medic at a wounded NPC holds exactly Revive')
assert(options[1].canInteract() == true)

handlers['humalike:npc:npcDownedState']('npc-1', { state = 'deceased' })
options = HumalikeTreatmentOptions('npc-1')
assert(#options == 1 and options[1].text == 'Send to mortuary',
    'a corpse offers a medic only the mortuary')
assert(options[1].canInteract() == true)
handlers['humalike:npc:treatmentRoles']({ medic = false, police = true })
options = HumalikeTreatmentOptions('npc-1')
assert(#options == 1 and options[1].text == 'Send to mortuary', 'police likewise')
handlers['humalike:npc:treatmentRoles']({ medic = false, police = false })
assert(#HumalikeTreatmentOptions('npc-1') == 0, 'a civilian sees nothing medical')
handlers['humalike:npc:treatmentRoles']({ medic = false, police = true })
handlers['humalike:npc:npcDownedState']('npc-1', { state = 'wounded' })
assert(#HumalikeTreatmentOptions('npc-1') == 0,
    'a cop waits for the body to be past helping')
handlers['humalike:npc:treatmentRoles']({ medic = true, police = false })
calls = {}
activePlayers = { 7 }
coordsByEntity[7] = vector3(1, 0, 0)
coordsByEntity[42] = vector3(0, 0, 0)
handlers['humalike:npc:npcDownedState']('npc-1', { state = 'revived', linger_ms = 30000 })
assert(HumalikeDownedState('npc-1') == nil, 'no longer down')
assert(indexOf('TaskStandStill'), 'held standing: ' .. names())
local lastFreeze = nil
for _, call in ipairs(calls) do
    if call.name == 'Freeze' then lastFreeze = call[1] end
end
assert(lastFreeze == false, 'the body is unfrozen when it gets up: ' .. names())
local blocked = nil
for _, call in ipairs(calls) do
    if call.name == 'Blocking' then blocked = call[1] end
end
assert(blocked == true, 'and not re-tasked out of the hold while it is held')
assert(indexOf('SetPedSuffersCriticalHits'), 'critical hits come back: ' .. names())
assert(indexOf('SetEntityCanBeDamaged'), 'and so does taking damage at all')
assert(indexOf('SetPedAsNoLongerNeeded'), 'the keep-alive is released on revive: ' .. names())
calls = {}
handlers['humalike:npc:npcDownedState']('npc-1', { state = 'gone' })
assert(indexOf('TriggerEvent:humalike:npc:npcBodyReleased'), 'the wheel comes off: ' .. names())
assert(indexOf('DeleteEntity'), 'the body is removed: ' .. names())
assert(HumalikeDownedState('npc-1') == nil)
calls = {}
dead = true
playingAnim = false
handlers['humalike:npc:npcDownedState']('npc-1', { state = 'wounded' })
assert(HumalikeDownedState('npc-1') == 'wounded')
local heldAfterDowning = false
calls = {}
for _, thread in ipairs(threads) do runThread(thread, 1) end
for _, call in ipairs(calls) do
    if call.name == 'TaskStandStill' or call.name == 'TaskWanderStandard' then
        heldAfterDowning = true
    end
end
assert(not heldAfterDowning, 'a downed body is not stood back up: ' .. names())
downed = HumalikeDownedState and nil
handlers['humalike:npc:npcDownedState']('npc-2', { state = 'deceased' })
LoadedPeds['npc-2'] = 42
assert(HumalikeDownedState('npc-2') == 'deceased')
LoadedPeds['npc-2'] = nil
AmbientPeds['npc-2'] = nil
calls = {}
local watchdog = threads[2]
now = 0
local base = 1000
GetGameTimer = function() return base end
runThread(watchdog, 1)          -- marks goneSince
base = base + 4000
runThread(watchdog, 1)          -- past grace -> release
assert(HumalikeDownedState('npc-2') == nil, 'the corpse is released, not recreated')
assert(not indexOf('TaskPlayAnim'), 'and a fresh ped is never posed as a corpse: ' .. names())
handlers['humalike:npc:npcDownedState']('npc-3', { state = 'deceased', entity_id = 77 })
AmbientNpcEntries = { ['npc-3'] = { entity_id = 77 } }
AmbientPeds['npc-3'] = 43
calls = {}
runThread(watchdog, 1)
assert(indexOf('TaskPlayAnim'), 'a corpse streaming in late is posed: ' .. names())
assert(HumalikeDownedState('npc-3') == 'deceased', 'and its options still stand')
AmbientNpcEntries = {}
handlers['humalike:npc:npcDownedState']('npc-5', { state = 'wounded', entity_id = 80, network_id = 800 })
networkedPeds[800] = 44
calls = {}
runThread(watchdog, 1)
assert(indexOf('TaskPlayAnim'), 'a lease-less body is found by network id and posed: ' .. names())
assert(HumalikeDownedState('npc-5') == 'wounded')
handlers['humalike:npc:npcDownedState']('npc-4', { state = 'deceased', entity_id = 90 })
AmbientNpcEntries['npc-4'] = { entity_id = 91 }
calls = {}
runThread(watchdog, 1)
assert(HumalikeDownedState('npc-4') == nil, 'a new body ends the corpse story')
assert(indexOf('TriggerEvent:humalike:npc:npcBodyReleased'), 'the wheel comes off: ' .. names())
calls = {}
for _, thread in ipairs(threads) do runThread(thread, 1) end
assert(indexOf('TriggerServerEvent:humalike:npc:requestDownedStates'),
    'the downed snapshot is requested at startup: ' .. names())

print('wounded_client: ok')
