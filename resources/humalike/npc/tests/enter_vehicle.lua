
Config = { Punch = { MaxDistance = 6.0 } }
NpcActions, NpcActionSustain, ActionControlledPeds = {}, {}, {}

local npc, partner, vehicle, unrelatedVehicle = 1, 10, 20, 21
local inVehicle, clears, enters, releases, timeouts = {}, {}, {}, 0, {}
local enterTaskStatus, poolCalls = 7, 0

function NpcActionPedInVehicle(ped) return inVehicle[ped] ~= nil end
function ActionTargetPed() return partner end
function GetVehiclePedIsIn(ped) return inVehicle[ped] or 0 end
function DoesEntityExist(entity) return entity == vehicle or entity == unrelatedVehicle end
function NetworkGetEntityIsNetworked(entity)
    return entity == vehicle or entity == unrelatedVehicle
end
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
    enterTaskStatus = 1
end
function SetTimeout(_delay, callback) timeouts[#timeouts + 1] = callback end
function GetScriptTaskStatus() return enterTaskStatus end
function GetHashKey(name) return name end
function GetEntityVelocity() return { x = 0, y = 0, z = 0 } end
function GetEntityCoords() return { x = 0, y = 0, z = 0 } end
function GetGamePool()
    poolCalls = poolCalls + 1
    return { unrelatedVehicle }
end

dofile('client/actions/enter_vehicle.lua')

inVehicle[partner] = vehicle
ActionControlledPeds[npc] = 'hands_up'
NpcActions.enter_vehicle(npc, { player_id = 7 })
assert(#clears == 1 and clears[1] == npc, 'enter clears the previous held pose')
assert(#enters == 1 and enters[1].ped == npc and enters[1].seat == 0)

NpcActionSustain.enter_vehicle(npc)
assert(#enters == 1, 'sustain must not restart an active enter task')

enterTaskStatus = 7
inVehicle[partner] = nil
NpcActionSustain.enter_vehicle(npc)
assert(#enters == 2 and enters[2].target == vehicle,
    'an interrupted task must retry the originally selected vehicle')
assert(poolCalls == 0, 'sustain must not switch to a newly nearest vehicle')
inVehicle[partner] = vehicle
NpcActions.enter_vehicle(npc, { player_id = 7 })
assert(#timeouts == 2 and #enters == 3)
timeouts[1]()
assert(ActionControlledPeds[npc] == 'enter_vehicle' and releases == 0,
    'an old timeout must not cancel a later attempt')

inVehicle[npc] = vehicle
NpcActionSustain.enter_vehicle(npc)
assert(#clears == 2, 'enter never clears a passenger seat task')
assert(#enters == 3 and releases == 1)
timeouts[2]()
assert(releases == 1, 'completed attempt state must be cleared')

print('enter_vehicle: ok')
