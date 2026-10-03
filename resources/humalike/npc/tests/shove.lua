function GetConvar(_name, default) return default end
dofile('config/convars.lua')
dofile('config/shared.lua')
AmbientNpcEntries = { ['ambient-1'] = { entity_id = 55 } }
AmbientPeds = {}
LoadedPeds = {}
ActionControlledPeds = {}

local threads = {}
local sent = {}
local pool = {}
local dead = {}
local downed = {}
local melee = {}
local ragdoll = {}
local touching = {}
local coords = {}
local speed = 0
local inVehicle = false
local playerDead = false
local velocity = { x = 1, y = 0, z = 0 } -- the direction; the speed above scales it

function CreateThread(callback) threads[#threads + 1] = callback end
function TriggerServerEvent(...) sent[#sent + 1] = { ... } end
function PlayerPedId() return 1 end
function DoesEntityExist(entity) return entity == 1 or pool[entity] ~= nil end
function IsPedAPlayer(ped) return ped == 1 end
function IsPedInAnyVehicle(ped) return ped == 1 and inVehicle end
function GetEntitySpeed() error('the speed is the length of the velocity the pulse already read') end
function GetEntityVelocity() return { x = velocity.x * speed, y = velocity.y * speed, z = velocity.z * speed } end
function GetEntityCoords(entity) return coords[entity] or { x = 2, y = 0, z = 0 } end
function GetGamePool() error('the shove detector never scans the ped pool') end
function IsEntityDead(ped) return ped == 1 and playerDead or dead[ped] == true end
function HumalikeDownedState(npcId) return downed[npcId] end
function IsPedInMeleeCombat(ped) return melee[ped] == true end
function IsPedRagdoll(ped) return ragdoll[ped] == true end
function IsEntityTouchingEntity(_, ped) return touching[ped] == true end
function HumalikeDebug() end

-- The tracker knows which registered peds stand within reach; ped 12 is
-- in no registry and never tracked.
local function near(npcId, ped)
    return { npcId = npcId, ped = ped, exists = true, dist2 = 4.0, x = 2, y = 0, z = 0 }
end
HumalikeWorldTrack = {
    tracks = { ['ambient-1'] = near('ambient-1', 10), ['static-1'] = near('static-1', 11),
        ['ambient-2'] = near('ambient-2', 13) },
    AnyWithin = function() return true end,
}

dofile('../world/client/pulse.lua')
dofile('client/shove.lua')
assert(#threads == 1, 'the shared pulse is the only thread')
coords[1] = { x = 0, y = 0, z = 0 }

pool = { [10] = true, [11] = true, [12] = true, [13] = true }
AmbientPeds = { ['ambient-1'] = 10, ['ambient-2'] = 13 }
LoadedPeds = { ['static-1'] = 11 }
touching = { [10] = true, [11] = true, [12] = true, [13] = true }

local playerReads, contactReads, exclusionReads = 0, 0, 0
local velocityOf, touchingOf, meleeOf = GetEntityVelocity, IsEntityTouchingEntity, IsPedInMeleeCombat
function GetEntityVelocity() playerReads = playerReads + 1 return velocityOf() end
function IsEntityTouchingEntity(a, b) contactReads = contactReads + 1 return touchingOf(a, b) end
function IsPedInMeleeCombat(ped)
    if ped ~= 1 then exclusionReads = exclusionReads + 1 end
    return meleeOf(ped)
end
HumalikeWorldTrack.AnyWithin = function() return false end
assert(HumalikeNpcShove.Tick(900) == 0 and playerReads == 0, 'with nobody in reach the player is not even looked at')
HumalikeWorldTrack.AnyWithin = function() return true end

assert(HumalikeNpcShove.Tick(1000) == 0 and #sent == 0 and contactReads == 0, 'standing still touches nobody')
-- A ped behind the player is never asked about; one in the way but not
-- touched is asked about contact only.
speed = 1.2
local were = touching
touching = {}
velocity = { x = -1, y = 0, z = 0 }
assert(HumalikeNpcShove.Tick(1010) == 0 and contactReads == 0, 'nobody in the direction of travel: no native per ped')
velocity = { x = 1, y = 0, z = 0 }
assert(HumalikeNpcShove.Tick(1020) == 0 and contactReads == 3 and exclusionReads == 0,
    'three peds ahead, none touched: one contact question each and nothing else')
touching = were
speed = 0
speed = 1.2
inVehicle = true
assert(HumalikeNpcShove.Tick(1100) == 0, 'a vehicle hit is not a shove')
inVehicle = false
assert(HumalikeNpcShove.Tick(1200) == 0 and #sent == 0, 'a contact is held, not reported at once')
assert(HumalikeNpcShove.Tick(1500) == 0, 'still inside the window')
assert(HumalikeNpcShove.Tick(1800) == 3 and #sent == 3, 'after the window three contacts report three')
local byNpc = {}
for _, row in ipairs(sent) do byNpc[row[2]] = row end
assert(byNpc['ambient-1'][1] == 'humalike:npc:npcShoved' and byNpc['ambient-1'][3] == 55
    and byNpc['ambient-1'][4] == 'bump', 'an ambient body carries its entity id')
assert(byNpc['static-1'][3] == nil and byNpc['static-1'][4] == 'bump', 'a static NPC has no entity id')
assert(byNpc['ambient-2'][3] == nil and byNpc['ambient-2'][4] == 'bump', 'an unknown entry still reports')
assert(HumalikeNpcShove.Tick(1900) == 0 and #sent == 3, 'a ped in no registry is nobody')
assert(HumalikeNpcShove.Tick(3000) == 0, 'still touching within the gap reports nothing')
HumalikeNpcShove.Tick(4800)
assert(HumalikeNpcShove.Tick(5400) == 3 and #sent == 6, 'after the gap contact is news again')

touching = { [10] = true }
HumalikeNpcShove.Tick(9000)
ragdoll[10] = true
HumalikeNpcShove.Tick(9200)
assert(#sent == 6, 'the fall inside the window is still being held')
assert(HumalikeNpcShove.Tick(9600) == 1 and #sent == 7 and sent[7][4] == 'knocked_down',
    'one report per contact, with the final intensity')
assert(HumalikeNpcShove.Tick(9700) == 0, 'the fall is not repeated')
ragdoll[10] = false
touching = {}
assert(HumalikeNpcShove.Tick(13000) == 0, 'no contact, nothing to say')
ragdoll[10] = true
assert(HumalikeNpcShove.Tick(13100) == 0 and HumalikeNpcShove.Tick(13800) == 0,
    'a ragdoll long after the last touch is not our doing')
touching = { [10] = true }
HumalikeNpcShove.Tick(14000)
assert(HumalikeNpcShove.Tick(14600) == 1 and sent[8][4] == 'bump',
    'a ped already on the ground was not knocked down')
ragdoll[10] = false

touching = { [10] = true, [11] = true, [13] = true }
speed = 0.4
HumalikeNpcShove.Tick(18000)
assert(HumalikeNpcShove.Tick(18600) == 0, 'below walking speed the NPC walked into you')
speed = 0.5
dead[11] = true
downed['ambient-2'] = 'wounded'
HumalikeNpcShove.Tick(18700)
assert(HumalikeNpcShove.Tick(19300) == 1 and sent[9][2] == 'ambient-1',
    'dead and downed bodies are never shoved')
dead[11] = false
downed['ambient-2'] = nil
melee[10] = true
ActionControlledPeds[11] = 'punch'
HumalikeNpcShove.Tick(23000)
assert(HumalikeNpcShove.Tick(23600) == 1 and sent[10][2] == 'ambient-2',
    'a ped in melee or under a punch action is not run into')
ActionControlledPeds[11] = 'wave'
melee[10] = false
HumalikeNpcShove.Tick(27000)
assert(HumalikeNpcShove.Tick(27600) == 3, 'other actions do not hide the contact')

ActionControlledPeds[11] = 'follow_player'
HumalikeNpcShove.Tick(31000)
assert(HumalikeNpcShove.Tick(31600) == 2 and sent[#sent][2] ~= 'static-1'
    and sent[#sent - 1][2] ~= 'static-1', 'a follower brushing past is not a shove')
ActionControlledPeds[11] = nil

HumalikeNpcShove.NoteDamage(10, 35000)
HumalikeNpcShove.Tick(35000)
assert(HumalikeNpcShove.Tick(35600) == 2 and sent[#sent][2] ~= 'ambient-1'
    and sent[#sent - 1][2] ~= 'ambient-1', 'a ped the player just hit was punched, not shoved')
melee[1] = true
HumalikeNpcShove.Tick(39000)
assert(HumalikeNpcShove.Tick(39600) == 0, 'a player in melee shoves nobody')
melee[1] = false

velocity = { x = -1, y = 0, z = 0 }
HumalikeNpcShove.Tick(43000)
assert(HumalikeNpcShove.Tick(43600) == 0, 'moving away from the ped: it walked into you')
velocity = { x = 1, y = 0, z = 0 }
playerDead = true
HumalikeNpcShove.Tick(47000)
assert(HumalikeNpcShove.Tick(47600) == 0, 'a corpse sliding into a ped is not a shove')
playerDead = false
ragdoll[1] = true
HumalikeNpcShove.Tick(51000)
assert(HumalikeNpcShove.Tick(51600) == 0, 'nor is a thrown player')
ragdoll[1] = false

touching = { [10] = true }
HumalikeNpcShove.Tick(70000)
assert(HumalikeNpcShove.Tick(70600) == 1, 'stale clocks are forgotten, not leaked')
pool[10] = nil
HumalikeNpcShove.Tick(74000)
assert(HumalikeNpcShove.Tick(74600) == 0, 'a deleted ped is skipped')
touching = { [11] = true }
HumalikeNpcShove.Tick(78000)
pool[11] = nil
assert(HumalikeNpcShove.Tick(78600) == 0, 'a ped deleted inside the window reports nothing')

print('shove: ok')
