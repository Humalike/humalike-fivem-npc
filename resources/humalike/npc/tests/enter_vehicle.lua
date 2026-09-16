
Config = { Punch = { MaxDistance = 6.0 } }
NpcActions, NpcActionSustain, ActionControlledPeds = {}, {}, {}

local npc, partner, vehicle, unrelatedVehicle, ownCar = 1, 10, 20, 21, 22
local inVehicle, clears, enters, leaves, releases = {}, {}, {}, {}, 0
local taskStatus, poolCalls, now = {}, 0, 1000
local pool = { unrelatedVehicle }

function NpcActionPedInVehicle(ped) return inVehicle[ped] ~= nil end
function ActionTargetPed() return partner end
function GetVehiclePedIsIn(ped) return inVehicle[ped] or 0 end
function DoesEntityExist(entity) return entity == vehicle or entity == unrelatedVehicle or entity == ownCar end
function NetworkGetEntityIsNetworked(entity) return DoesEntityExist(entity) end
function GetPedInVehicleSeat(entity, seat)
    if entity == vehicle and seat == -1 and inVehicle[partner] == vehicle then return partner end
    return 0
end
function ClearPedTasks(ped) clears[#clears + 1] = ped end
function MarkActionControl(ped, key) ActionControlledPeds[ped] = key end
function ReleaseActionControl(ped)
    ActionControlledPeds[ped] = nil
    releases = releases + 1
end
function TaskEnterVehicle(ped, target, timeout, seat)
    enters[#enters + 1] = { ped = ped, target = target, timeout = timeout, seat = seat }
    taskStatus[ped] = { SCRIPT_TASK_ENTER_VEHICLE = 1 }
end
function TaskLeaveVehicle(ped, target)
    leaves[#leaves + 1] = { ped = ped, target = target }
    taskStatus[ped] = { SCRIPT_TASK_LEAVE_VEHICLE = 1 }
end
function GetScriptTaskStatus(ped, hash) return taskStatus[ped] and taskStatus[ped][hash] or 7 end
function GetHashKey(name) return name end
function GetGameTimer() return now end
function GetEntityVelocity() return { x = 0, y = 0, z = 0 } end
local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, {
        __sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end,
    })
end
function GetEntityCoords() return vec(0, 0, 0) end
function GetGamePool()
    poolCalls = poolCalls + 1
    return pool
end
function print() end

dofile('client/actions/enter_vehicle.lua')

-- A lift into the partner's car: the held pose is cleared and a passenger seat taken.
inVehicle[partner] = vehicle
ActionControlledPeds[npc] = 'hands_up'
NpcActions.enter_vehicle(npc, { player_id = 7 })
assert(#clears == 1 and clears[1] == npc, 'enter clears the previous held pose')
assert(#enters == 1 and enters[1].ped == npc and enters[1].seat == 0)
assert(ActionControlledPeds[npc] == 'enter_vehicle')

NpcActionSustain.enter_vehicle(npc)
assert(#enters == 1, 'sustain must not restart an active enter task')

taskStatus[npc] = {}
inVehicle[partner] = nil
NpcActionSustain.enter_vehicle(npc)
assert(#enters == 2 and enters[2].target == vehicle,
    'an interrupted task must retry the originally selected vehicle')
assert(poolCalls == 0, 'sustain must not switch to a newly nearest vehicle')

inVehicle[npc] = vehicle
NpcActionSustain.enter_vehicle(npc)
assert(#clears == 1, 'enter never clears a seated ped')
assert(releases == 1 and ActionControlledPeds[npc] == nil, 'seated in the target: done')

-- Told again while already in the partner's car: nothing to do.
inVehicle[partner] = vehicle
NpcActions.enter_vehicle(npc, { player_id = 7 })
assert(#enters == 2 and releases == 2, 'already in the partner\'s car: nothing to do')

-- The attempt gives up after its window.
inVehicle[npc] = nil
taskStatus[npc] = {}
NpcActions.enter_vehicle(npc, { player_id = 7 })
assert(#enters == 3)
now = now + 20001
NpcActionSustain.enter_vehicle(npc)
assert(releases == 3 and ActionControlledPeds[npc] == nil, 'timed out: the body is given back')
now = 1000

-- A driver at its own wheel asked into the partner's car: gives its own up,
-- climbs OUT first, and only then walks over -- and stays under the action
-- until it sits in the TARGET, never released while still in its own car.
local dismissed = 0
HumalikeNpcDriving = {
    Dismiss = function(ped) assert(ped == npc); dismissed = dismissed + 1 end,
    OwnVehicle = function() return ownCar end,
}
local ownDriver = true
function NpcActionDrivesOwnVehicle(ped) return ped == npc and ownDriver end
inVehicle[npc] = ownCar
inVehicle[partner] = vehicle
taskStatus[npc] = {}
local entersBefore, leavesBefore, releasesBefore = #enters, #leaves, releases
NpcActions.enter_vehicle(npc, { player_id = 7 })
assert(dismissed == 1, 'the driver gives its own car up')
assert(#leaves == leavesBefore + 1 and leaves[#leaves].target == ownCar, 'it climbs out of its own car first')
assert(#enters == entersBefore, 'no enter task while still seated in its own car')
NpcActionSustain.enter_vehicle(npc)
assert(releases == releasesBefore, 'still in its own car: NOT released (the old early-release bug)')
assert(#leaves == leavesBefore + 1, 'a running leave task is left alone')
inVehicle[npc] = nil
taskStatus[npc] = {}
NpcActionSustain.enter_vehicle(npc)
assert(#enters == entersBefore + 1 and enters[#enters].target == vehicle and enters[#enters].seat == 0,
    'out of its own car: it walks to the partner\'s')
inVehicle[npc] = vehicle
NpcActionSustain.enter_vehicle(npc)
assert(releases == releasesBefore + 1, 'seated in the partner\'s car: done')

-- The partner stands OUTSIDE beside their parked car: a seated driver still
-- gets out and boards the nearest car that is neither its own nor the one it
-- sits in -- "get in my car" from the pavement.
ownDriver = true
inVehicle[npc] = ownCar
inVehicle[partner] = nil
pool = { ownCar, unrelatedVehicle }
taskStatus[npc] = {}
entersBefore, leavesBefore, releasesBefore = #enters, #leaves, releases
NpcActions.enter_vehicle(npc, { player_id = 7 })
assert(dismissed == 2 and #leaves == leavesBefore + 1, 'partner on foot: the driver still leaves its own car')
inVehicle[npc] = nil
taskStatus[npc] = {}
NpcActionSustain.enter_vehicle(npc)
assert(#enters == entersBefore + 1 and enters[#enters].target == unrelatedVehicle,
    'and boards the nearest other car, never its own')
inVehicle[npc] = unrelatedVehicle
NpcActionSustain.enter_vehicle(npc)
assert(releases == releasesBefore + 1)

-- With no other car in sight, a driver stays in its own.
pool = { ownCar }
inVehicle[npc] = ownCar
entersBefore, leavesBefore, releasesBefore = #enters, #leaves, releases
NpcActions.enter_vehicle(npc, { player_id = 7 })
assert(dismissed == 2 and #leaves == leavesBefore and #enters == entersBefore and releases == releasesBefore + 1,
    'no other car: a driver stays in its own')

-- On foot beside its own parked car with no partner car in sight, a lift is
-- never into its own: that car is enter_own_vehicle's.
ownDriver = false
inVehicle[npc] = nil
taskStatus[npc] = {}
pool = { ownCar }
entersBefore = #enters
NpcActions.enter_vehicle(npc, { player_id = 7 })
assert(#enters == entersBefore, 'the nearest car being its own, there is nothing to get into')
pool = { ownCar, unrelatedVehicle }
NpcActions.enter_vehicle(npc, { player_id = 7 })
assert(#enters == entersBefore + 1 and enters[#enters].target == unrelatedVehicle,
    'somebody else\'s parked car is a lift as before')
print('enter_vehicle: ok')
