function GetConvar(_name, default) return default end
dofile('config/convars.lua')
dofile('config/shared.lua')
NpcActions, NpcActionSustain, ActionControlledPeds = {}, {}, {}

local npc, player, ownCar, playerCar = 1, 10, 20, 21
local inVehicle, seats, coords = {}, {}, {}
local clears, leaves, enters, releases, marks = {}, {}, {}, 0, {}
local reclaimed, dismissed, resumed = 0, 0, 0
local taskStatus = {}
local now = 1000
local drivesOwn = false

local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, {
        __sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end,
    })
end
coords[npc], coords[ownCar], coords[playerCar] = vec(0, 0, 0), vec(10, 0, 0), vec(3, 0, 0)

function GetGameTimer() return now end
function GetEntityCoords(entity) return coords[entity] end
function GetVehiclePedIsIn(ped) return inVehicle[ped] or 0 end
function GetPedInVehicleSeat(vehicle, seat) return seats[vehicle] and seats[vehicle][seat] or 0 end
function HumalikePlayerInVehicle(vehicle) return inVehicle[player] == vehicle end
function GetScriptTaskStatus(ped, hash) return taskStatus[ped] and taskStatus[ped][hash] or 7 end
function GetHashKey(name) return name end
function ClearPedTasks(ped) clears[#clears + 1] = ped end
function TaskLeaveVehicle(ped, vehicle) leaves[#leaves + 1] = { ped = ped, vehicle = vehicle } end
function TaskEnterVehicle(ped, vehicle, timeout, seat)
    enters[#enters + 1] = { ped = ped, vehicle = vehicle, timeout = timeout, seat = seat }
    taskStatus[ped] = { SCRIPT_TASK_ENTER_VEHICLE = 1 }
end
function MarkActionControl(ped, key) ActionControlledPeds[ped] = key; marks[#marks + 1] = key end
function ReleaseActionControl(ped) ActionControlledPeds[ped] = nil; releases = releases + 1 end
function NpcActionPedInVehicle(ped) return inVehicle[ped] ~= nil end
function NpcActionDrivesOwnVehicle(ped) return ped == npc and drivesOwn end
function print() end
local own = ownCar
HumalikeNpcDriving = {
    OwnVehicleInReach = function(ped)
        assert(ped == npc)
        if not own then return nil, 'no vehicle of its own' end
        if #(coords[own] - coords[npc]) > Config.Vehicles.ReturnDistance then return nil, 'own vehicle out of reach' end
        local occupant = seats[own] and seats[own][-1] or 0
        if (occupant ~= 0 and occupant ~= npc) or inVehicle[player] == own then return nil, 'own vehicle taken' end
        return own
    end,
    TaskRunning = function(ped, hash) return (taskStatus[ped] and taskStatus[ped][hash] or 7) <= 1 end,
    Reclaim = function(ped) assert(ped == npc); reclaimed = reclaimed + 1 end,
    Dismiss = function(ped) assert(ped == npc); dismissed = dismissed + 1 end,
    Resume = function(ped) assert(ped == npc); resumed = resumed + 1; return true end,
}

dofile('client/actions/enter_own_vehicle.lua')

-- On foot beside the player's car, told to get back in its own: it walks to
-- ITS car and takes the wheel, ignoring the player's car right next to it.
ActionControlledPeds[npc] = 'hold_position'
NpcActions.enter_own_vehicle(npc, { player_id = 7 })
assert(reclaimed == 1, 'the car is its own again')
assert(#clears == 1 and clears[1] == npc, 'the held pose is cleared first')
assert(marks[1] == 'enter_own_vehicle' and ActionControlledPeds[npc] == 'enter_own_vehicle')
assert(#enters == 1 and enters[1].vehicle == ownCar and enters[1].seat == -1,
    'it boards its own driver seat, not the player\'s car')
assert(enters[1].timeout == Config.Vehicles.EnterTimeoutMs)

NpcActionSustain.enter_own_vehicle(npc)
assert(#enters == 1, 'a running enter task is left alone')
taskStatus[npc] = {}
NpcActionSustain.enter_own_vehicle(npc)
assert(#enters == 2 and enters[2].vehicle == ownCar, 'a dropped enter task is re-issued')

-- Seated at its own wheel: the deed is done and the drive resumes.
inVehicle[npc] = ownCar
seats[ownCar] = { [-1] = npc }
drivesOwn = true
NpcActionSustain.enter_own_vehicle(npc)
assert(releases == 1 and resumed == 1 and reclaimed == 2 and ActionControlledPeds[npc] == nil,
    'back at the wheel: released and driving off')

-- Already driving when told to get in and leave: it just drives off.
NpcActions.enter_own_vehicle(npc, {})
assert(releases == 2 and resumed == 2 and #enters == 2)

-- A passenger in the player's car told to get back to its own: out first,
-- then over to its own seat.
drivesOwn = false
inVehicle[npc] = playerCar
seats[ownCar] = {}
NpcActions.enter_own_vehicle(npc, { player_id = 7 })
assert(#clears == 1, 'never clears tasks on a seated ped')
assert(#leaves == 1 and leaves[1].vehicle == playerCar, 'it leaves the player\'s car first')
assert(#enters == 2, 'no enter task while still seated elsewhere')
taskStatus[npc] = { SCRIPT_TASK_LEAVE_VEHICLE = 1 }
NpcActionSustain.enter_own_vehicle(npc)
assert(#leaves == 1, 'a running leave task is left alone')
inVehicle[npc] = nil
taskStatus[npc] = {}
NpcActionSustain.enter_own_vehicle(npc)
assert(#enters == 3 and enters[3].vehicle == ownCar, 'out of the car: it walks to its own')

-- The player took its seat meanwhile: it gives the car up and stays on foot.
seats[ownCar] = { [-1] = player }
NpcActionSustain.enter_own_vehicle(npc)
assert(dismissed == 1 and releases == 3 and ActionControlledPeds[npc] == nil)

-- Its car is too far, or gone, or already occupied: nothing is attempted.
seats[ownCar] = {}
local entersBefore, releasesBefore = #enters, releases
coords[ownCar] = vec(Config.Vehicles.ReturnDistance + 1, 0, 0)
NpcActions.enter_own_vehicle(npc, {})
assert(#enters == entersBefore and releases == releasesBefore + 1, 'out of reach: released untouched')
coords[ownCar] = vec(10, 0, 0)
inVehicle[player] = ownCar
NpcActions.enter_own_vehicle(npc, {})
assert(#enters == entersBefore and releases == releasesBefore + 2, 'a player inside: not its to take')
inVehicle[player] = nil
own = nil
NpcActions.enter_own_vehicle(npc, {})
assert(#enters == entersBefore and releases == releasesBefore + 3, 'no car of its own: nothing to do')
own = ownCar

-- The walk gives up after the return timeout.
taskStatus[npc] = {}
NpcActions.enter_own_vehicle(npc, {})
assert(#enters == entersBefore + 1)
now = now + Config.Vehicles.ReturnTimeoutMs + 1
NpcActionSustain.enter_own_vehicle(npc)
assert(ActionControlledPeds[npc] == nil, 'timed out: the body is given back')

-- A migrated body sustains with no local attempt: it rebuilds one from its own car.
now = 5000
ActionControlledPeds[npc] = 'enter_own_vehicle'
taskStatus[npc] = {}
local before = #enters
NpcActionSustain.enter_own_vehicle(npc)
assert(#enters == before + 1 and enters[#enters].vehicle == ownCar, 'the new owner resumes the walk')
print('enter_own_vehicle: ok')
