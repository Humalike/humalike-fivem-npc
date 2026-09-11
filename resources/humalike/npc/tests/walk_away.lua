
Config = {
    ActionSustainTickMs = 250,
    WalkAway = { Distance = 30.0, ArriveRange = 3.0 },
}

local npcPed, partner = 1, 10
local living = { [npcPed] = true, [partner] = true }
local threads, walks, wanders, bags = {}, {}, {}, {}
local npcAt = { x = 0.0, y = 0.0, z = 0.0 }
local taskStatus = 1
local nowMs = 1000
function GetGameTimer() return nowMs end

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
dofile('client/actions/walk_away.lua')
NpcActions['walk_away'](npcPed, { player_id = 7 })
assert(ActionControlledPeds[npcPed] == 'walk_away', 'the deed owns the ped')
assert(#walks == 1 and walks[1].x == -30.0 and walks[1].y == 0.0,
    'the destination is straight away from the partner')
assert(type(bags['humalike_action']) == 'table'
    and bags['humalike_action'].key == 'walk_away'
    and bags['humalike_action'].params.x == -30.0,
    'the deed and its destination ride the statebag for the next owner')
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
nowMs = nowMs + 59000
NpcActionSustain['walk_away'](npcPed)
assert(ActionControlledPeds[npcPed] == 'walk_away', 'still trying inside the allowance')
nowMs = nowMs + 2000
NpcActionSustain['walk_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'an unreachable walk is abandoned, not sustained forever')
assert(#wanders == 2, 'and the ped still gets its wander back')
ActionControlledPeds[npcPed] = 'walk_away'
ActionParams[npcPed] = { bogus = true }
NpcActionSustain['walk_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'a destination-less walk is released')

print('walk_away: ok')
