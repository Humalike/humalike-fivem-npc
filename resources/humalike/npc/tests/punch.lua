Config = { Punch = { MaxDistance = 4.0, DurationMs = 4000 } }
NpcActions, ActionControlledPeds = {}, {}

local npc, target = 1, 2
local timers, attributes, clears, releases = {}, {}, 0, 0

function NpcActionPedInVehicle() return false end
function ActionTargetPed() return target end
function SetCurrentPedWeapon() end
function GetHashKey(name) return name end
function SetPedCombatAttributes(ped, attribute, enabled)
    attributes[#attributes + 1] = { ped = ped, attribute = attribute, enabled = enabled }
end
function MarkActionControl(ped, key) ActionControlledPeds[ped] = key end
function TaskCombatPed() end
function SetTimeout(_, callback) timers[#timers + 1] = callback end
function ReleaseActionControl(ped)
    ActionControlledPeds[ped] = nil
    releases = releases + 1
end
function DoesEntityExist() return true end
function ClearPedTasks() clears = clears + 1 end

dofile('client/actions/punch.lua')

NpcActions.punch(npc, { player_id = 7 })
assert(attributes[1].attribute == 46 and attributes[1].enabled == true)
ActionControlledPeds[npc] = 'follow_player'
timers[1]()
assert(attributes[2].attribute == 46 and attributes[2].enabled == false,
    'punch always restores BF_ALWAYS_FIGHT after its window')
assert(ActionControlledPeds[npc] == 'follow_player' and releases == 0 and clears == 0,
    'the expired punch does not disturb the new action owner')

print('punch: ok')
