
function GetConvar(_name, default) return default end
dofile('config/shared.lua')

local npcPed, bench = 1, 40
local threads, seats, scenarios, clears, bags = {}, {}, {}, {}, {}
local benchAt = nil
local usingScenario = false
local nowMs = 1000
local inVehicle = false
function GetGameTimer() return nowMs end
function GetVehiclePedIsIn() return inVehicle and 30 or 0 end
function GetEntityCoords(entity)
    if entity == bench then return benchAt end
    return { x = 0.0, y = 0.0, z = 0.0 }
end
function DoesEntityExist(entity) return entity == npcPed or (entity == bench and benchAt ~= nil) end
function GetClosestObjectOfType(_x, _y, _z, radius, model)
    if benchAt and model == 'prop_bench_01a' and benchAt.x < radius then return bench end
    return 0
end
function GetHashKey(name) return name end
function TaskUseNearestScenarioToCoord(ped, x, y, z, range, duration)
    seats[#seats + 1] = { ped = ped, x = x, y = y, z = z, range = range, duration = duration }
end
function TaskStartScenarioInPlace(ped, name) scenarios[#scenarios + 1] = { ped = ped, name = name } end
function IsPedUsingAnyScenario() return usingScenario end
function ClearPedTasks(ped) clears[#clears + 1] = ped end
function CreateThread(fn) threads[#threads + 1] = fn end
function AddStateBagChangeHandler() end
function NetworkHasControlOfEntity() return true end
function IsEntityDead() return false end
function IsPedRagdoll() return false end
function IsPedAPlayer() return false end
function SetBlockingOfNonTemporaryEvents() end
function SetPedKeepTask() end
function Entity(_ped)
    return { state = { set = function(_self, key, value) bags[key] = value end } }
end

dofile('client/reactions.lua')
dofile('client/actions/state.lua')
dofile('client/actions/sit_down.lua')

benchAt = { x = 4.0, y = 0.0, z = 0.0 }
NpcActions['sit_down'](npcPed, {})
assert(ActionControlledPeds[npcPed] == 'sit_down', 'the deed owns the ped')
assert(#seats == 1 and seats[1].x == 4.0 and seats[1].range == Config.SitDown.BenchScenarioRange
    and seats[1].duration == -1, 'a bench within reach is walked to and sat on')
assert(#scenarios == 0, 'no ground sit while a bench is on offer')
assert(type(bags['humalike_action']) == 'table' and bags['humalike_action'].key == 'sit_down'
    and bags['humalike_action'].params.mode == 'bench'
    and bags['humalike_action'].params.x == 4.0,
    'the seat rides the statebag for the next owner')

nowMs = nowMs + 3000
NpcActionSustain['sit_down'](npcPed)
assert(#seats == 1, 'still walking to the bench inside the settle window')
usingScenario = true
nowMs = nowMs + 20000
NpcActionSustain['sit_down'](npcPed)
assert(#seats == 1 and #scenarios == 0 and ActionControlledPeds[npcPed] == 'sit_down',
    'a seated ped is left alone however long it sits')

usingScenario = false
NpcActionSustain['sit_down'](npcPed)
assert(#seats == 2 and seats[2].x == 4.0, 'a seat that ended (or a new owner) sits again')
nowMs = nowMs + Config.SitDown.BenchSettleMs + 1
NpcActionSustain['sit_down'](npcPed)
assert(#scenarios == 1 and scenarios[1].name == 'WORLD_HUMAN_PICNIC',
    'a bench that never took falls back to the ground')
assert(bags['humalike_action'].params.mode == 'ground', 'and the fallback is what the next owner sees')
nowMs = nowMs + Config.SitDown.GroundSettleMs + 1
NpcActionSustain['sit_down'](npcPed)
assert(ActionControlledPeds[npcPed] == nil and bags['humalike_action'] == nil,
    'a ground sit that never played gives up instead of retrying forever')

benchAt = nil
local seatsBefore, scenariosBefore = #seats, #scenarios
NpcActions['sit_down'](npcPed, {})
assert(#seats == seatsBefore and #scenarios == scenariosBefore + 1
    and bags['humalike_action'].params.mode == 'ground',
    'no bench nearby means sitting where you stand')
usingScenario = true
NpcActionSustain['sit_down'](npcPed)
assert(ActionControlledPeds[npcPed] == 'sit_down')

inVehicle = true
usingScenario = false
scenariosBefore = #scenarios
local clearsBefore = #clears
NpcActions['sit_down'](npcPed, {})
assert(#scenarios == scenariosBefore, 'a passenger is already sitting')
ActionControlledPeds[npcPed] = 'sit_down'
ActionParams[npcPed] = { mode = 'ground' }
NpcActionSustain['sit_down'](npcPed)
assert(ActionControlledPeds[npcPed] == nil and #scenarios == scenariosBefore
    and #clears == clearsBefore,
    'a seated ped that ended up in a vehicle drops the seat without touching the ride')
inVehicle = false

ActionControlledPeds[npcPed] = 'sit_down'
ActionParams[npcPed] = { bogus = true }
NpcActionSustain['sit_down'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'a seat-less sit is released')

print('sit_down: ok')
