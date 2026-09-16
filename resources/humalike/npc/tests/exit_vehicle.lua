Config = { Follow = { VehicleTaskTimeoutMs = 10000 } }
NpcActions, NpcActionSustain, ActionControlledPeds = {}, {}, {}

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
HumalikeNpcDriving = { Dismiss = function(ped) assert(ped == npc); dismissed = dismissed + 1 end }
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
print('exit_vehicle: ok')
