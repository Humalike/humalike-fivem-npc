Config = { AmbientControl = { StandTaskDurationMs = 2000 } }
NpcActions = {}

local action = 'follow_player'
local clears, stands, wanders, stopFollowing, walks = 0, 0, 0, 0, 0
local inVehicle = false

function NpcActionPedInVehicle() return inVehicle end
function ReleaseActionControl() action = nil end
function ClearPedTasks() clears = clears + 1 end
function TaskStandStill(_, duration)
    assert(duration == 2000)
    stands = stands + 1
end
function TaskWanderStandard() wanders = wanders + 1 end
function BeginStopFollowing()
    stopFollowing = stopFollowing + 1
    action = nil
end

HumalikeNpcDriving = HumalikeNpcDriving or { DrivesOwnVehicle = function() return false end }
NpcActionDrivesOwnVehicle = NpcActionDrivesOwnVehicle or function() return false end
dofile('client/actions/hold_position.lua')
dofile('client/actions/release_movement.lua')
NpcActions.walk_away = function(_ped, params)
    assert(params.player_id == 7)
    action = 'walk_away'
    walks = walks + 1
end

NpcActions.hold_position(42, {})
assert(action == nil and stopFollowing == 1 and stands == 1,
    'hold ends follow before standing still')

action = 'hold_position'
NpcActions.release_movement(42, { player_id = 7 })
assert(action == 'walk_away' and walks == 1 and clears == 0 and wanders == 0,
    'release visibly walks away through the sustained locomotion lane')

inVehicle = true
action = 'follow_player'
NpcActions.release_movement(42, {})
assert(action == nil and stopFollowing == 2 and walks == 1 and wanders == 0,
    'a passenger finishes the existing safe exit path before wandering')

print('movement_control: ok')

-- A population driver at its own wheel: "stop" brakes and stays seated; it is
-- never treated as a passenger to send out of the car.
local braked = 0
HumalikeNpcDriving = { Brake = function(ped) assert(ped == 42); braked = braked + 1 end }
local ownDriver = true
function NpcActionDrivesOwnVehicle(ped) return ped == 42 and ownDriver end
inVehicle = true
action = 'follow_player'
local before = stopFollowing
NpcActions.hold_position(42, {})
assert(action == nil and braked == 1 and stopFollowing == before,
    'a driver told to stop brakes instead of leaving its car')
ownDriver = false
NpcActions.hold_position(42, {})
assert(stopFollowing == before + 1 and braked == 1, 'a passenger still climbs out as before')
print('movement_control driver cases: ok')
