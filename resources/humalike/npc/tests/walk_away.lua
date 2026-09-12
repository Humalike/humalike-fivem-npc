
function GetConvar(_name, default) return default end
dofile('config/shared.lua')

local npcPed, partner = 1, 10
local living = { [npcPed] = true, [partner] = true }
local threads, walks, wanders, bags = {}, {}, {}, {}
local npcAt = { x = 0.0, y = 0.0, z = 0.0 }
local taskStatus = 1
local nowMs = 1000
local cloudSeconds = 1000
function GetGameTimer() return nowMs end
function GetCloudTimeAsInt() return cloudSeconds end
function GetVehiclePedIsIn() return 0 end

local mt = {}
mt.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, mt)
end
mt.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function at(x, y, z) return setmetatable({ x = x, y = y, z = z }, mt) end

function GetEntityCoords(ped)
    if ped == npcPed then return at(npcAt.x, npcAt.y, npcAt.z) end
    return at(5.0, 0.0, 0.0)
end
function GetEntityHeading() return 0.0 end
function DoesEntityExist(ped) return living[ped] == true end
function GetActivePlayers() return { 110 } end
function GetPlayerPed() return partner end
function GetPlayerFromServerId(serverId) return serverId == 7 and 110 or -1 end
function TaskFollowNavMeshToCoord(ped, x, y, z)
    walks[#walks + 1] = { ped = ped, x = x, y = y, z = z }
end
function TaskWanderStandard(ped) wanders[#wanders + 1] = ped end
function ClearPedTasks() end
function GetScriptTaskStatus() return taskStatus end
function GetHashKey(name) return name end
function CreateThread(fn) threads[#threads + 1] = fn end
function AddStateBagChangeHandler() end
function NetworkHasControlOfEntity() return true end
function IsEntityDead() return false end
function IsPedRagdoll() return false end
function IsPedAPlayer() return false end
function SetBlockingOfNonTemporaryEvents() end
function SetPedKeepTask() end
function Entity(ped)
    return { state = { set = function(_self, key, value) bags[key] = value end } }
end

dofile('client/reactions.lua')
dofile('client/actions/state.lua')
dofile('client/actions/leave.lua')
dofile('client/actions/walk_away.lua')
NpcActions['walk_away'](npcPed, { player_id = 7 })
assert(ActionControlledPeds[npcPed] == 'walk_away', 'the deed owns the ped')
assert(#walks == 1 and walks[1].x == -30.0 and walks[1].y == 0.0,
    'the destination is straight away from the partner')
assert(type(bags['humalike_action']) == 'table'
    and bags['humalike_action'].key == 'walk_away'
    and bags['humalike_action'].params.x == -30.0,
    'the deed and its destination ride the statebag for the next owner')
assert(bags['humalike_action'].params.ends_at == cloudSeconds + 60,
    'and so does the expiry, in server-synced seconds')
taskStatus = 7
NpcActionSustain['walk_away'](npcPed)
assert(#walks == 2 and walks[2].x == -30.0, 'a dropped walk is re-issued')
taskStatus = 1
npcAt = { x = -15.0, y = 0.0, z = 0.0 }
NpcActionSustain['walk_away'](npcPed)
assert(#walks == 2, 'a healthy walk is left alone')
assert(ActionControlledPeds[npcPed] == 'walk_away')
npcAt = { x = -29.0, y = 0.0, z = 0.0 }
NpcActionSustain['walk_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'arrival releases the deed')
assert(#wanders == 1, 'and the ped wanders off as itself')
assert(bags['humalike_action'] == nil, 'the statebag is cleared for good')
npcAt = { x = 0.0, y = 0.0, z = 0.0 }
NpcActions['walk_away'](npcPed, { player_id = 7 })
cloudSeconds = cloudSeconds + 59
NpcActionSustain['walk_away'](npcPed)
assert(ActionControlledPeds[npcPed] == 'walk_away', 'still trying inside the allowance')
cloudSeconds = cloudSeconds + 2
NpcActionSustain['walk_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'an unreachable walk is abandoned, not sustained forever')
assert(#wanders == 2, 'and the ped still gets its wander back')
ActionControlledPeds[npcPed] = 'walk_away'
ActionParams[npcPed] = { bogus = true }
NpcActionSustain['walk_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'a destination-less walk is released')

ActionControlledPeds[npcPed] = 'walk_away'
ActionParams[npcPed] = { x = -30.0, y = 0.0, z = 0.0, ends_at = cloudSeconds - 1 }
local wandersBefore = #wanders
NpcActionSustain['walk_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil and #wanders == wandersBefore + 1,
    'a walk resumed after its expiry is released on the first sustain')
ActionControlledPeds[npcPed] = 'walk_away'
ActionParams[npcPed] = { x = -30.0, y = 0.0, z = 0.0, ends_at = cloudSeconds + 5 }
taskStatus = 7
local walksBefore = #walks
NpcActionSustain['walk_away'](npcPed)
assert(ActionControlledPeds[npcPed] == 'walk_away' and #walks == walksBefore + 1,
    'a walk resumed with time left is re-issued')

print('walk_away: ok')
