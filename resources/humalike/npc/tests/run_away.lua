function GetConvar(_name, default) return default end
dofile('config/shared.lua')

local npcPed, partner = 1, 10
local living = { [npcPed] = true, [partner] = true }
local threads, flees, walks, wanders, blends, bags = {}, {}, {}, {}, {}, {}
local npcAt = { x = 0.0, y = 0.0, z = 0.0 }
local partnerAt = { x = 5.0, y = 0.0, z = 0.0 }
local taskStatus = 1
local nowMs = 1000
local cloudSeconds = 5000
local inVehicle = 0
local stopFollowing = 0
local safeCoord
function GetGameTimer() return nowMs end
function GetCloudTimeAsInt() return cloudSeconds end

local mt = {}
mt.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, mt)
end
mt.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function at(x, y, z) return setmetatable({ x = x, y = y, z = z }, mt) end

function GetEntityCoords(ped)
    if ped == npcPed then return at(npcAt.x, npcAt.y, npcAt.z) end
    return at(partnerAt.x, partnerAt.y, partnerAt.z)
end
function GetEntityHeading() return 0.0 end
function DoesEntityExist(ped) return living[ped] == true end
function GetActivePlayers() return { 110 } end
function GetPlayerPed() return partner end
function GetPlayerFromServerId(serverId) return serverId == 7 and 110 or -1 end
function GetVehiclePedIsIn() return inVehicle end
function BeginStopFollowing() stopFollowing = stopFollowing + 1 end
function GetSafeCoordForPed(x, y, z)
    if safeCoord then return true, safeCoord end
    return false, nil
end
function TaskSmartFleePed(ped, target, distance, duration)
    flees[#flees + 1] = { ped = ped, target = target, distance = distance, duration = duration }
end
function TaskFollowNavMeshToCoord(ped, x, y, z, speed)
    walks[#walks + 1] = { ped = ped, x = x, y = y, z = z, speed = speed }
end
function TaskWanderStandard(ped) wanders[#wanders + 1] = ped end
function SetPedMaxMoveBlendRatio(ped, value) blends[#blends + 1] = { ped, value } end
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
local walkRate = 0.8
function Entity(ped)
    return { state = setmetatable({ humalike_walk_rate = walkRate },
        { __index = { set = function(_self, key, value) bags[key] = value end } }) }
end
local paceCalls = {}
HumalikeNpcPopulationClient = {
    OwnPace = function(ped) paceCalls[#paceCalls + 1] = { ped, 'own' } end,
    RestorePace = function(ped)
        paceCalls[#paceCalls + 1] = { ped, 'restore' }
        SetPedMaxMoveBlendRatio(ped, walkRate or 3.0)
    end,
}

dofile('client/reactions.lua')
dofile('client/actions/state.lua')
dofile('client/actions/leave.lua')
dofile('client/actions/run_away.lua')
NpcActions['run_away'](npcPed, { player_id = 7 })
assert(ActionControlledPeds[npcPed] == 'run_away', 'the deed owns the ped')
assert(#flees == 1 and flees[1].target == partner and flees[1].distance == 60.0
    and flees[1].duration == 12000, 'the ped flees the partner for the configured distance and time')
assert(blends[#blends][2] == 2.1, 'a runner sprints, whatever pace the street gave it')
assert(type(bags['humalike_action']) == 'table' and bags['humalike_action'].key == 'run_away'
    and bags['humalike_action'].params.x == -60.0,
    'the deed and its point ride the statebag for the next owner')
assert(bags['humalike_action'].params.ends_at == cloudSeconds + 12,
    'and so does the expiry, in server-synced seconds')
taskStatus = 7
NpcActionSustain['run_away'](npcPed)
assert(#flees == 2, 'a dropped flee is re-issued')
taskStatus = 1
npcAt = { x = -30.0, y = 0.0, z = 0.0 }
blends = {}
NpcActionSustain['run_away'](npcPed)
assert(#flees == 2 and ActionControlledPeds[npcPed] == 'run_away', 'a healthy flee is left alone')
assert(#blends == 1 and blends[1][2] == 2.1, 'the run blend is re-asserted every tick')
npcAt = { x = -56.0, y = 0.0, z = 0.0 }
NpcActionSustain['run_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'reaching the distance releases the deed')
assert(#wanders == 1, 'and the ped wanders off as itself')
assert(paceCalls[#paceCalls][2] == 'restore' and blends[#blends][2] == 0.8,
    'the population client hands the pace back on release')
assert(bags['humalike_action'] == nil, 'the statebag is cleared for good')

npcAt = { x = 0.0, y = 0.0, z = 0.0 }
NpcActions['run_away'](npcPed, { player_id = 7 })
cloudSeconds = cloudSeconds + 11
NpcActionSustain['run_away'](npcPed)
assert(ActionControlledPeds[npcPed] == 'run_away', 'still running inside the allowance')
cloudSeconds = cloudSeconds + 2
NpcActionSustain['run_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'the run ends when its time is up')
assert(#wanders == 2)

ActionControlledPeds[npcPed] = 'run_away'
ActionParams[npcPed] = { x = -60.0, y = 0.0, z = 0.0, player_id = 7, ends_at = cloudSeconds - 1 }
NpcActionSustain['run_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil and #wanders == 3,
    'a run resumed after its expiry is released on the first sustain')
ActionControlledPeds[npcPed] = 'run_away'
ActionParams[npcPed] = { x = -60.0, y = 0.0, z = 0.0, player_id = 7, ends_at = cloudSeconds + 3 }
taskStatus = 7
blends = {}
NpcActionSustain['run_away'](npcPed)
assert(ActionControlledPeds[npcPed] == 'run_away' and #flees == 4 and flees[4].target == partner,
    'a run resumed with time left re-issues the flee from the partner')
assert(blends[1][2] == 2.1 and blends[#blends][2] == 2.1, 'at the run blend')
cloudSeconds = cloudSeconds + 3
NpcActionSustain['run_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'and still ends on the original clock')

npcAt = { x = 0.0, y = 0.0, z = 0.0 }
NpcActions['run_away'](npcPed, { player_id = 7 })
local fleesBefore, walksBefore = #flees, #walks
npcAt = { x = -40.0, y = 0.0, z = 0.0 }
partnerAt = { x = 5.0, y = 0.0, z = 0.0 }
taskStatus = 7
NpcActionSustain['run_away'](npcPed)
assert(#flees == fleesBefore and #walks == walksBefore + 1, 'a partner 45 m away is no flee target')
assert(walks[#walks].x == -60.0 and walks[#walks].y == 0.0 and walks[#walks].speed == 2.1,
    'the ped runs on to the stored point instead')
npcAt = { x = -57.0, y = 0.0, z = 0.0 }
NpcActionSustain['run_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'and arrival there releases the deed')
taskStatus = 1

living[partner] = nil
npcAt = { x = 0.0, y = 0.0, z = 0.0 }
NpcActions['run_away'](npcPed, {})
assert(walks[#walks].x == 0.0 and walks[#walks].y == 60.0 and walks[#walks].speed == 2.1,
    'with nobody to flee from the ped sprints away along its heading')
ActionControlledPeds[npcPed] = 'run_away'
ActionParams[npcPed] = { bogus = true }
NpcActionSustain['run_away'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'a pointless run is released')

npcAt = { x = 0.0, y = 0.0, z = 0.0 }
safeCoord = { x = 2.0, y = 58.0, z = 1.0 }
NpcActions['run_away'](npcPed, {})
assert(bags['humalike_action'].params.x == 2.0 and bags['humalike_action'].params.y == 58.0
    and bags['humalike_action'].params.z == 1.0, 'the stored point is snapped onto walkable ground')
safeCoord = nil
NpcActionLeave.Stop(npcPed)

inVehicle = 5
local fleesInVehicle = #flees
NpcActions['run_away'](npcPed, { player_id = 7 })
assert(stopFollowing == 1 and #flees == fleesInVehicle and ActionControlledPeds[npcPed] == nil,
    'a seated body climbs out first')
inVehicle = 0

print('run_away: ok')
