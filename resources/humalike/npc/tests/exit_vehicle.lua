Config = { Follow = { VehicleTaskTimeoutMs = 10000 }, Vehicles = { ReturnDistance = 60.0 } }
NpcActions, NpcActionSustain, ActionControlledPeds, ActionParams = {}, {}, {}, {}

local npc, vehicle = 1, 20
local inVehicle, leaveTaskStatus, leaves, releases = vehicle, 7, 0, 0
local now = 1000

function GetVehiclePedIsIn() return inVehicle end
function GetGameTimer() return now end
function MarkActionControl(ped, key) ActionControlledPeds[ped] = key end
function ReleaseActionControl(ped)
    ActionControlledPeds[ped] = nil
    releases = releases + 1
end
function TaskLeaveVehicle(ped, targetVehicle, flag)
    assert(ped == npc and targetVehicle == vehicle and flag == 0)
    leaves = leaves + 1
    leaveTaskStatus = 1
end
function GetScriptTaskStatus() return leaveTaskStatus end
function GetHashKey(name) return name end

dofile('client/actions/exit_vehicle.lua')

NpcActions.exit_vehicle(npc, {})
assert(leaves == 1 and ActionControlledPeds[npc] == 'exit_vehicle')

NpcActionSustain.exit_vehicle(npc)
assert(leaves == 1, 'sustain must not restart an active leave task')

leaveTaskStatus = 7
NpcActionSustain.exit_vehicle(npc)
assert(leaves == 2, 'sustain retries a dropped leave task')

now = 11000
NpcActionSustain.exit_vehicle(npc)
assert(releases == 1 and ActionControlledPeds[npc] == nil,
    'an unreachable exit is abandoned after the vehicle task timeout')

ActionControlledPeds[npc] = 'exit_vehicle'
now = 12000
NpcActionSustain.exit_vehicle(npc)
now = 22000
NpcActionSustain.exit_vehicle(npc)
assert(releases == 2 and ActionControlledPeds[npc] == nil,
    'an adopting owner grants the sustained exit one bounded allowance')

now = 23000
NpcActions.exit_vehicle(npc, {})
inVehicle = 0
NpcActionSustain.exit_vehicle(npc)
assert(releases == 3 and ActionControlledPeds[npc] == nil)


-- A population driver told to get out gives its car up for good.
local dismissed = 0
HumalikeNpcDriving = {
    Dismiss = function(ped) assert(ped == npc); dismissed = dismissed + 1 end,
    IsDismissed = function() return dismissed > 0 end,
    OwnVehicle = function() return nil end,
}
local ownDriver = true
function NpcActionDrivesOwnVehicle(ped) return ped == npc and ownDriver end
inVehicle = vehicle
now = 30000
NpcActions.exit_vehicle(npc, {})
assert(dismissed == 1 and leaves == 4, 'a driver getting out dismisses its own car')
ownDriver = false
ActionControlledPeds[npc] = nil
NpcActions.exit_vehicle(npc, {})
assert(dismissed == 1, 'a passenger has no car of its own to dismiss')

-- Out of SOMEBODY ELSE'S car with its own standing near, getting out is the
-- start of going home: the walk-back deed takes over instead of a release.
local ownCar, homeCalls = 30, 0
local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, {
        __sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end,
    })
end
local coords = { [npc] = vec(0, 0, 0), [ownCar] = vec(11, 0, 0) }
function GetEntityCoords(entity) return coords[entity] end
function GetPedInVehicleSeat() return 0 end
function HumalikePlayerInVehicle() return false end
NpcActions.enter_own_vehicle = function(ped, params)
    assert(ped == npc and type(params) == 'table')
    homeCalls = homeCalls + 1
    ActionControlledPeds[ped] = 'enter_own_vehicle'
end
HumalikeNpcDriving.OwnVehicle = function() return ownCar end
ownDriver = false -- it got out of its OWN car earlier (dismissed) and then rode along
inVehicle = vehicle
ActionControlledPeds[npc] = nil
ActionParams[npc] = { player_id = 7 }
local releasesBefore = releases
NpcActions.exit_vehicle(npc, {})
inVehicle = 0
NpcActionSustain.exit_vehicle(npc)
assert(homeCalls == 1 and releases == releasesBefore and ActionControlledPeds[npc] == 'enter_own_vehicle',
    'out of their car with its own near: it goes home instead of being released')

-- Its own car too far, or none at all: out and released as before.
coords[ownCar] = vec(61, 0, 0)
inVehicle = vehicle
ActionControlledPeds[npc] = nil
NpcActions.exit_vehicle(npc, {})
inVehicle = 0
NpcActionSustain.exit_vehicle(npc)
assert(homeCalls == 1 and releases == releasesBefore + 1, 'own car out of reach: just out')
coords[ownCar] = vec(11, 0, 0)

-- Out of its OWN car on request: it stays out, however close the car is.
ownDriver = true
inVehicle = vehicle
ActionControlledPeds[npc] = nil
NpcActions.exit_vehicle(npc, {})
assert(dismissed == 2)
inVehicle = 0
NpcActionSustain.exit_vehicle(npc)
assert(homeCalls == 1 and releases == releasesBefore + 2, 'got out of its own car: never sent straight back')
print('exit_vehicle: ok')
