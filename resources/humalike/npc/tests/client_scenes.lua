function GetConvar(_name, default) return default end
dofile('config/shared.lua')

local handlers = {}
local threads = {}
local calls = {}
local pool = {}
local netEntities = {}
local inVehicle = {}
local seats = {}
local pedVehicle = {}
local stopped = {}
local dead = {}
local usingScenario = {}
local speeds = {}
local taskStatus = {}
local players = {}
local ENTER, FOLLOW, WANDER = 25, 38, 32 -- GetHashKey stub = name length
local coords = {}
local safeCoords = {}

function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
function CreateThread(callback) threads[#threads + 1] = callback end
function GetCurrentResourceName() return 'humalike' end
function DoesEntityExist(entity) return pool[entity] == true end
function NetworkDoesEntityExistWithNetworkId(networkId) return netEntities[networkId] ~= nil end
function NetworkGetEntityFromNetworkId(networkId) return netEntities[networkId] or 0 end
function IsEntityDead(ped) return dead[ped] == true end
function IsPedRagdoll() return false end
function IsPedUsingAnyScenario(ped) return usingScenario[ped] == true end
function IsPedStopped(ped) return stopped[ped] == true end
function IsPedInAnyVehicle(ped) return inVehicle[ped] ~= nil end
function IsPedInVehicle(ped, vehicle) return inVehicle[ped] == vehicle end
function GetVehiclePedIsIn(ped) return inVehicle[ped] or 0 end
function GetPedInVehicleSeat(vehicle, seat) return seats[vehicle] and seats[vehicle][seat] or 0 end
function GetEntitySpeed(entity) return speeds[entity] or 0.0 end
function GetScriptTaskStatus(ped, hash) return taskStatus[ped] and taskStatus[ped][hash] or 7 end
function IsPedAPlayer(ped) return players[ped] == true end
local function taskRunning(ped, hash, running)
    taskStatus[ped] = taskStatus[ped] or {}
    taskStatus[ped][hash] = running and 1 or 7
end
function GetHashKey(name) return #name end
function GetEntityCoords(entity) return coords[entity] or { x = 0, y = 0, z = 0 } end
function GetSafeCoordForPed(x, y, z)
    if safeCoords.deny then return false, nil end
    return true, { x = x, y = y, z = z }
end
local function record(name)
    return function(...) calls[#calls + 1] = { name, ... } end
end
TaskWanderStandard = record('wander')
TaskFollowToOffsetOfEntity = record('follow')
TaskGoStraightToCoord = record('go')
TaskStartScenarioInPlace = record('scenario')
TaskTurnPedToFaceCoord = record('turn')
TaskStandStill = record('stand')
TaskVehicleTempAction = record('temp')
TaskEnterVehicle = record('enter')
TaskVehicleDriveWander = record('drive')
TaskVehicleFollow = record('vfollow')
SetVehicleEngineOn = record('engine')
ClearPedTasks = record('clear')

dofile('client/scenes.lua')
assert(#threads == 0)

local function named(name, from)
    local rows = {}
    for index = from or 1, #calls do
        if calls[index][1] == name then rows[#rows + 1] = calls[index] end
    end
    return rows
end
local function last()
    return calls[#calls]
end
local function reset()
    calls = {}
end
local function scene(fields)
    local row = { id = 's1', archetype = 'corner', slot = 0, ax = 100, ay = 200, az = 30,
        heading = 90, ox = 0.0, oy = 0.0, leader_net = 501 }
    for key, value in pairs(fields) do row[key] = value end
    return row
end
local Scenes = HumalikeNpcScenesClient
local held = { humalike_scene_held = true }
local free = {}
for ped = 10, 30 do pool[ped] = true end
netEntities[501] = 10
netEntities[601] = 40
pool[40] = true

-- corner: turn to the anchor first, the slot's scenario once the turn is over.
Scenes.Configure(10, scene({ slot = 0 }), free, 1000)
assert(#calls == 1 and last()[1] == 'turn' and last()[2] == 10)
assert(last()[3] == 100 and last()[4] == 200 and last()[5] == 30, 'faces the anchor')
Scenes.Refresh(10, scene({ slot = 0 }), free, 1500)
assert(#calls == 1, 'nothing until the turn is over')
Scenes.Refresh(10, scene({ slot = 0 }), free, 2000)
assert(#calls == 2 and last()[1] == 'scenario' and last()[3] == 'WORLD_HUMAN_HANG_OUT_STREET')
assert(last()[4] == 0 and last()[5] == true)
usingScenario[10] = true
Scenes.Refresh(10, scene({ slot = 0 }), free, 30000)
assert(#calls == 2, 'a ped in its scenario is left alone')
usingScenario[10] = nil
stopped[10] = true
Scenes.Refresh(10, scene({ slot = 0 }), free, 31000)
Scenes.Refresh(10, scene({ slot = 0 }), free, 41000)
assert(#calls == 3 and last()[1] == 'scenario', 'idle for ScenarioIdleMs restarts the scenario')
assert(#named('turn') == 1, 'the turn is issued once')
reset()
Scenes.Configure(11, scene({ slot = 1 }), free, 1000)
Scenes.Refresh(11, scene({ slot = 1 }), free, 2000)
assert(last()[1] == 'scenario' and last()[3] == 'WORLD_HUMAN_SMOKING', 'slot-indexed scenario')
Scenes.Configure(12, scene({ slot = 6 }), free, 1000)
Scenes.Refresh(12, scene({ slot = 6 }), free, 2000)
assert(last()[3] == 'WORLD_HUMAN_SMOKING', 'the list wraps')
Scenes.Configure(13, scene({ archetype = 'sidewalk', slot = 0 }), free, 1000)
Scenes.Refresh(13, scene({ archetype = 'sidewalk', slot = 0 }), free, 2000)
assert(last()[1] == 'scenario' and last()[3] == 'WORLD_HUMAN_LEANING')
Scenes.Configure(14, scene({ archetype = 'sidewalk', slot = 3 }), free, 1000)
Scenes.Refresh(14, scene({ archetype = 'sidewalk', slot = 3 }), free, 2000)
assert(last()[3] == 'WORLD_HUMAN_STAND_IMPATIENT')

-- walk: the leader wanders, followers keep their offset behind the leader ped.
reset()
Scenes.Configure(10, scene({ archetype = 'walk', slot = 0 }), free, 1000)
assert(#calls == 1 and last()[1] == 'wander' and last()[2] == 10)
Scenes.Configure(15, scene({ archetype = 'walk', slot = 1, ox = 0.0, oy = -1.3 }), free, 1000)
assert(last()[1] == 'follow' and last()[2] == 15 and last()[3] == 10, 'follows the leader entity')
assert(last()[4] == 0.0 and last()[5] == -1.3 and last()[6] == 0.0 and last()[7] == 1.0)
assert(last()[8] == -1 and last()[9] == 1.0 and last()[10] == true)
Scenes.Configure(16, scene({ archetype = 'walk', slot = 2, leader_net = 999 }), free, 1000)
assert(last()[1] == 'wander' and last()[2] == 16, 'no local leader: wander')
local leaderless = scene({ archetype = 'walk', slot = 2 })
leaderless.leader_net = nil
Scenes.Configure(17, leaderless, free, 1000)
assert(last()[1] == 'wander' and last()[2] == 17)
stopped[15] = true
taskRunning(15, FOLLOW, true)
Scenes.Refresh(15, scene({ archetype = 'walk', slot = 1 }), free, 3000)
Scenes.Refresh(15, scene({ archetype = 'walk', slot = 1 }), free, 60000)
assert(last()[2] == 17, 'a follower standing behind a waiting leader is never re-tasked on idle')
taskRunning(15, FOLLOW, false)
Scenes.Refresh(15, scene({ archetype = 'walk', slot = 1 }), free, 61000)
assert(last()[1] == 'follow' and last()[2] == 15, 'a dropped follow task is re-issued')
taskRunning(15, FOLLOW, true)
-- A wandering follower takes its leader up as soon as it is local; a dead leader loses it.
reset()
Scenes.Refresh(16, scene({ archetype = 'walk', slot = 2, leader_net = 999 }), free, 62000)
assert(#calls == 0, 'a leaderless follower keeps wandering')
netEntities[999] = 10
Scenes.Refresh(16, scene({ archetype = 'walk', slot = 2, leader_net = 999 }), free, 62500)
assert(#calls == 1 and last()[1] == 'follow' and last()[3] == 10, 'the leader arrived: follow')
taskRunning(16, FOLLOW, true)
dead[10] = true
Scenes.Refresh(16, scene({ archetype = 'walk', slot = 2, leader_net = 999 }), free, 63000)
assert(#calls == 2 and last()[1] == 'wander' and last()[2] == 16, 'a dead leader: wander')
dead[10] = nil
netEntities[999] = nil
-- A re-slotted crew: the promoted follower leads on the next refresh, the rest re-target.
reset()
stopped[15] = nil
Scenes.Refresh(15, scene({ archetype = 'walk', slot = 1 }), free, 64000)
assert(#calls == 0, 'a moving follower with its role is left alone')
netEntities[502] = 15
Scenes.Refresh(15, scene({ archetype = 'walk', slot = 0, leader_net = 502 }), free, 7000)
assert(#calls == 1 and last()[1] == 'wander' and last()[2] == 15, 'slot 1 -> 0: the ped leads at once')
Scenes.Refresh(16, scene({ archetype = 'walk', slot = 1, ox = 0.0, oy = -1.3, leader_net = 502 }), free, 7000)
assert(#calls == 2 and last()[1] == 'follow' and last()[2] == 16 and last()[3] == 15,
    'slot 2 -> 1: follows the new leader')
taskRunning(16, FOLLOW, true)
Scenes.Refresh(15, scene({ archetype = 'walk', slot = 0, leader_net = 502 }), free, 7500)
assert(#calls == 2, 'an unchanged role is not re-issued')
Scenes.Refresh(11, scene({ slot = 0 }), free, 8000)
assert(last()[1] == 'scenario' and last()[2] == 11 and last()[3] == 'WORLD_HUMAN_HANG_OUT_STREET',
    'a corner ped re-slotted to 0 switches scenario without turning again')

-- run: the leader sprints to a far pavement point, followers run behind.
reset()
coords[10] = { x = 0, y = 0, z = 5 }
Scenes.Configure(10, scene({ archetype = 'run', slot = 0 }), free, 1000)
local go = last()
assert(go[1] == 'go' and go[2] == 10 and go[6] == 2.0 and go[7] == -1)
local distance = math.sqrt(go[3] * go[3] + go[4] * go[4])
assert(math.abs(distance - 120.0) < 0.01 and go[5] == 5, '120 m away')
Scenes.Refresh(10, scene({ archetype = 'run', slot = 0 }), free, 2000)
assert(#calls == 1, 'still on the way')
coords[10] = { x = go[3] - 3, y = go[4], z = 5 }
Scenes.Refresh(10, scene({ archetype = 'run', slot = 0 }), free, 3000)
assert(#calls == 2 and last()[1] == 'go', 'within 8 m: a new target')
coords[10] = { x = 0, y = 0, z = 5 }
safeCoords.deny = true
reset()
Scenes.Configure(18, scene({ archetype = 'run', slot = 0 }), free, 1000)
assert(#calls == 1 and last()[1] == 'wander' and last()[2] == 18, 'no pavement anywhere: wander once')
Scenes.Refresh(18, scene({ archetype = 'run', slot = 0 }), free, 2000)
Scenes.Refresh(18, scene({ archetype = 'run', slot = 0 }), free, 5900)
assert(#calls == 1, 'no new search and no new wander before 5 s')
Scenes.Refresh(18, scene({ archetype = 'run', slot = 0 }), free, 6000)
assert(#calls == 2 and last()[1] == 'wander', 'the search is retried every 5 s')
safeCoords.deny = nil
Scenes.Refresh(18, scene({ archetype = 'run', slot = 0 }), free, 11000)
assert(#calls == 3 and last()[1] == 'go', 'and runs once pavement is found')
Scenes.Configure(15, scene({ archetype = 'run', slot = 1 }), free, 1000)
assert(last()[1] == 'follow' and last()[7] == 2.0, 'followers run')

-- held on foot: tasks cleared once, then stand still every refresh; released: re-applied.
reset()
Scenes.Refresh(11, scene({ slot = 1 }), held, 5000)
assert(#calls == 2 and calls[1][1] == 'clear' and calls[1][2] == 11)
assert(calls[2][1] == 'stand' and calls[2][2] == 11 and calls[2][3] == 2000)
Scenes.Refresh(11, scene({ slot = 1 }), held, 6000)
assert(#calls == 3 and last()[1] == 'stand', 'cleared once, stood again')
Scenes.Refresh(11, scene({ slot = 1 }), free, 7000)
assert(#calls == 5 and calls[4][1] == 'clear' and calls[5][1] == 'scenario'
    and calls[5][3] == 'WORLD_HUMAN_SMOKING', 'released: the scenario comes back at once')
reset()
Scenes.Configure(19, scene({ slot = 2 }), held, 1000)
assert(calls[1][1] == 'clear' and calls[2][1] == 'stand', 'configured while held: stands')

-- car: the driver drives, a passenger sits; anyone outside re-enters their seat.
reset()
local car = scene({ archetype = 'car', slot = 0, seat = -1, vehicle_net = 601 })
inVehicle[20] = 40
seats[40] = { [-1] = 20 }
Scenes.Configure(20, car, free, 1000)
assert(#calls == 2 and calls[1][1] == 'engine' and calls[1][2] == 40 and calls[1][3] == true)
assert(calls[2][1] == 'drive' and calls[2][2] == 20 and calls[2][3] == 40 and calls[2][4] == 12.0
    and calls[2][5] == 786603)
taskRunning(20, WANDER, true)
speeds[40] = 8.0
Scenes.Refresh(20, car, free, 2000)
assert(#calls == 2, 'a moving driver with a drive task is left alone')
speeds[40] = 0.0
Scenes.Refresh(20, car, free, 3000)
Scenes.Refresh(20, car, free, 40000)
assert(#calls == 2, 'a driver waiting at a light keeps its drive task, however long')
speeds[40] = 8.0
taskRunning(20, WANDER, false)
Scenes.Refresh(20, car, free, 41000)
assert(#calls == 4 and last()[1] == 'drive', 'no drive task: drive again')
taskRunning(20, WANDER, true)
reset()
Scenes.Refresh(20, car, held, 13000)
assert(#calls == 2 and calls[1][1] == 'clear' and calls[2][1] == 'temp')
assert(calls[2][2] == 20 and calls[2][3] == 40 and calls[2][4] == 27 and calls[2][5] == 2000, 'a held driver brakes')
Scenes.Refresh(20, car, held, 14000)
assert(#calls == 3 and last()[1] == 'temp')
Scenes.Refresh(20, car, free, 15000)
assert(#calls == 5 and calls[4][1] == 'engine' and calls[5][1] == 'drive', 'released: drives again without a clear')
reset()
local passenger = scene({ archetype = 'car', slot = 1, seat = 0, vehicle_net = 601 })
inVehicle[21] = 40
Scenes.Configure(21, passenger, free, 1000)
Scenes.Refresh(21, passenger, free, 20000)
Scenes.Refresh(21, passenger, held, 21000)
assert(#calls == 1 and calls[1][1] == 'clear', 'a passenger sits, held or not')
inVehicle[21] = nil
Scenes.Refresh(21, passenger, free, 22000)
assert(#calls == 3 and calls[2][1] == 'clear', 'the hold ended on foot: tasks are cleared once more')
assert(last()[1] == 'enter' and last()[2] == 21 and last()[3] == 40
    and last()[4] == 15000 and last()[5] == 0 and last()[6] == 1.0 and last()[7] == 1 and last()[8] == 0,
    'a passenger outside re-enters its seat')
reset()
inVehicle[20] = nil
seats[40] = {}
Scenes.Refresh(20, car, free, 50000)
assert(#calls == 1 and last()[1] == 'enter' and last()[5] == -1, 'the driver re-enters the driver seat')
taskRunning(20, ENTER, true)
Scenes.Refresh(20, car, free, 51000)
assert(#calls == 1, 'not while the enter task runs')
taskRunning(20, ENTER, false)
Scenes.Refresh(20, car, free, 52000)
Scenes.Refresh(20, car, free, 64000)
assert(#calls == 1, 'a dropped enter task is not re-issued within 15 s of the last attempt')
Scenes.Refresh(20, car, free, 65000)
assert(#calls == 2 and last()[1] == 'enter', 'then once more')
seats[40] = { [-1] = 21 }
Scenes.Refresh(20, car, free, 80000)
assert(#calls == 3 and last()[1] == 'wander' and last()[2] == 20, 'someone took the seat: the driver walks off')
Scenes.Refresh(20, car, free, 95000)
Scenes.Refresh(20, car, free, 110000)
assert(#calls == 3, 'and is never sent back')
seats[40] = { [0] = 1 }
players[1] = true
inVehicle[21] = nil
reset()
Scenes.Refresh(21, passenger, free, 111000)
assert(#calls == 1 and last()[1] == 'wander' and last()[2] == 21, 'a player in the vehicle ends the ride')
Scenes.Refresh(21, passenger, free, 130000)
assert(#calls == 1)
players[1] = nil
seats[40] = { [-1] = 20 }
inVehicle[20] = 40
reset()
local orphan = scene({ archetype = 'car', slot = 0, seat = -1, vehicle_net = 777 })
inVehicle[22] = nil
stopped[22] = true
Scenes.Configure(22, orphan, free, 1000)
assert(last()[1] == 'wander' and last()[2] == 22, 'a vanished vehicle leaves the body walking')

-- bikes: followers trail the leader's bike; alone they wander.
reset()
local pack = scene({ archetype = 'bikes', slot = 1, seat = -1, vehicle_net = 602, leader_net = 501 })
netEntities[602] = 41
pool[41] = true
inVehicle[23] = 41
inVehicle[10] = 40
Scenes.Configure(23, pack, free, 1000)
assert(calls[1][1] == 'engine' and calls[1][2] == 41)
assert(calls[2][1] == 'vfollow' and calls[2][2] == 23 and calls[2][3] == 41 and calls[2][4] == 40
    and calls[2][5] == 786603 and calls[2][6] == 12.0 and calls[2][7] == 6)
inVehicle[10] = nil
Scenes.Configure(23, pack, free, 2000)
assert(last()[1] == 'drive' and last()[2] == 23, 'no leader bike: wander')
taskRunning(23, WANDER, true)
speeds[41] = 8.0
reset()
Scenes.Refresh(23, pack, free, 3000)
assert(#calls == 0, 'a wandering follower with its drive task is left alone')
inVehicle[10] = 40
Scenes.Refresh(23, pack, free, 4000)
assert(#calls == 2 and last()[1] == 'vfollow' and last()[4] == 40, 'the leader bike is back: follow it again')
speeds[41] = 0.0
Scenes.Refresh(23, pack, free, 5000)
Scenes.Refresh(23, pack, free, 34000)
assert(#calls == 2, 'a following bike is not re-issued for lacking the wander task, nor within 30 s stopped')
Scenes.Refresh(23, pack, free, 35000)
assert(#calls == 4 and last()[1] == 'vfollow', 'a 30 s stall re-issues the follow')
speeds[41] = 8.0
dead[10] = true
Scenes.Refresh(23, pack, free, 36000)
assert(#calls == 6 and last()[1] == 'drive', 'a dead leader: drive-wander')
dead[10] = nil
Scenes.Refresh(23, pack, free, 37000)
assert(#calls == 8 and last()[1] == 'vfollow', 'alive again: follow')
inVehicle[10] = nil
reset()
local lead = scene({ archetype = 'bikes', slot = 0, seat = -1, vehicle_net = 601 })
inVehicle[10] = 40
Scenes.Configure(10, lead, free, 1000)
assert(last()[1] == 'drive' and last()[2] == 10, 'the lead bike wanders')

-- Brake: a seated scene driver brakes for a hold on itself; anyone else does not.
reset()
inVehicle[20] = 40
seats[40] = { [-1] = 20, [0] = 21 }
inVehicle[21] = 40
assert(Scenes.Brake(20, car) == true and last()[1] == 'temp' and last()[2] == 20 and last()[4] == 27)
assert(Scenes.Brake(21, passenger) == false, 'a passenger has nothing to brake')
inVehicle[20] = nil
assert(Scenes.Brake(20, car) == false, 'a driver on foot stands like anyone')
inVehicle[20] = 40
assert(Scenes.Brake(11, scene({ slot = 1 })) == false)

-- Reapply resets the hold and turn bookkeeping.
reset()
Scenes.Refresh(11, scene({ slot = 1 }), held, 30000)
Scenes.Reapply(11, scene({ slot = 1 }), free, 31000)
assert(last()[1] == 'scenario', 'reapply issues the archetype')
Scenes.Refresh(11, scene({ slot = 1 }), held, 32000)
assert(last()[1] == 'stand' and calls[#calls - 1][1] == 'clear', 'a later hold clears again')
dead[11] = true
reset()
Scenes.Refresh(11, scene({ slot = 1 }), held, 33000)
Scenes.Configure(11, scene({ slot = 1 }), free, 34000)
assert(#calls == 0, 'a dead body is left alone')
dead[11] = nil

-- Forget drops bookkeeping for unseen peds: a corner ped turns again after it.
reset()
Scenes.Forget({})
Scenes.Configure(10, scene({ slot = 0 }), free, 1000)
assert(last()[1] == 'turn')
Scenes.Forget({ [10] = true })
Scenes.Refresh(10, scene({ slot = 0 }), free, 2000)
assert(last()[1] == 'scenario', 'a seen ped keeps its turn state')
handlers['onResourceStop']('humalike')
Scenes.Configure(10, scene({ slot = 0 }), free, 3000)
assert(last()[1] == 'turn', 'a resource stop resets everything')

-- Wiring: the population tick hands scene bodies to the scene module.
local sent
local sceneBags = {}
local heldBags = {}
local kinds = {}
local bodyKinds = {}
local owned = {}
local blendCalls = {}
local paceCalls = {}
local visible = {}
local nodes = {}
function TriggerServerEvent(...) sent = { ... } end
function PlayerPedId() return 1 end
function IsSphereVisible(x) return visible[x] == true end
function GetClosestVehicleNodeWithHeading(x, y, z)
    local node = nodes[x]
    if node then return true, { x = node[1], y = node[2], z = node[3] }, node[4] end
    return false, nil, 0.0
end
function GetGamePool()
    local peds = {}
    for ped in pairs(pool) do if kinds[ped] then peds[#peds + 1] = ped end end
    table.sort(peds)
    return peds
end
players[1] = true
function Entity(ped)
    return { state = {
        humalike_npc_kind = kinds[ped],
        humalike_body_kind = bodyKinds[ped],
        humalike_body_id = 'body-' .. ped,
        humalike_scene = sceneBags[ped],
        humalike_scene_held = heldBags[ped],
        humalike_walk_rate = 1.0,
    } }
end
function SetCreateRandomCops() end
function SetCreateRandomCopsNotOnScenarios() end
function SetCreateRandomCopsOnScenarios() end
function SetPedDensityMultiplierThisFrame() end
function SetScenarioPedDensityMultiplierThisFrame() end
function NetworkHasControlOfEntity(ped) return owned[ped] == true end
function SetBlockingOfNonTemporaryEvents() end
function TaskSetBlockingOfNonTemporaryEvents() end
function SetPedMinMoveBlendRatio(ped, value) blendCalls[#blendCalls + 1] = { ped, 'min', value } end
function SetPedMaxMoveBlendRatio(ped, value) blendCalls[#blendCalls + 1] = { ped, 'max', value } end
function SetPedMoveRateOverride(ped, rate) paceCalls[#paceCalls + 1] = { ped, rate } end
function IsActionControlled() return false end
function HumalikeAmbientControlHeldPed() return false end
function DownedNpcOf() return nil end
local fleeing, ragdoll = {}, {}
function IsPedFleeing(ped) return fleeing[ped] == true end
function IsPedRagdoll(ped) return ragdoll[ped] == true end
function GetGameTimer() return 0 end
function GetActivePlayers() return {} end
function GetPlayerPed() return 0 end
function GetEntityPopulationType() return 7 end
function IsEntityAMissionEntity() return false end
function GetPedType() return 4 end
function SetEntityAsMissionEntity() end
function DeleteEntity() end
HumalikeNpcStyle = { ApplySeed = function() return true end }
dofile('client/reactions.lua')
dofile('client/population.lua')

pool[1] = true
nodes[10] = { 60, 1, 30.5, 270 }
local candidates = { { x = 10, y = 0, z = 30, heading = 90 } }
local point = HumalikeNpcPopulationClient.SelectSpawnPoint(candidates, 'vehicle')
assert(point.x == 60 and point.y == 1 and point.z == 30.5 and point.heading == 270,
    'vehicle mode returns the road node with its heading')
visible[60] = true
assert(HumalikeNpcPopulationClient.SelectSpawnPoint(candidates, 'vehicle') == nil, 'a visible node is rejected')
visible[60] = nil
nodes[10] = { 3, 0, 30, 0 }
assert(HumalikeNpcPopulationClient.SelectSpawnPoint(candidates, 'vehicle') == nil, 'a node near the player too')
assert(HumalikeNpcPopulationClient.SelectSpawnPoint(candidates, 'foot') == nil, 'foot mode never uses nodes')
nodes[10] = { 60, 1, 30.5, 270 }
handlers['humalike:npc:populationSpawnPoint']('req-v', candidates, 'vehicle')
assert(sent[2] == 'req-v' and sent[3].x == 60 and sent[3].heading == 270)

pool = { [50] = true, [51] = true, [52] = true, [53] = true, [54] = true }
kinds = { [50] = 'population', [51] = 'population', [52] = 'population', [53] = 'population',
    [54] = 'population' }
bodyKinds = { [50] = 'persona', [51] = 'persona', [52] = 'persona', [53] = 'extra', [54] = 'persona' }
owned = { [50] = true, [51] = true, [52] = true, [53] = true, [54] = true }
netEntities[701] = 50
sceneBags[50] = scene({ id = 'sc-a', archetype = 'walk', slot = 0, leader_net = 701 })
sceneBags[51] = scene({ id = 'sc-a', archetype = 'walk', slot = 1, ox = 0.0, oy = -1.3, leader_net = 701 })
sceneBags[52] = scene({ id = 'sc-b', archetype = 'run', slot = 0 })
sceneBags[53] = scene({ id = 'sc-a', archetype = 'walk', slot = 2, leader_net = nil })
coords[52] = { x = 0, y = 0, z = 0 }
reset()
blendCalls = {}
HumalikeNpcPopulationClient.Tick(1000, false)
local wanders, follows, goes = named('wander'), named('follow'), named('go')
assert(#wanders == 3 and wanders[1][2] == 50 and wanders[2][2] == 53 and wanders[3][2] == 54,
    'the leader, the leaderless follower and the lone body wander')
assert(#follows == 1 and follows[1][2] == 51 and follows[1][3] == 50, 'the follower trails the local leader')
assert(#goes == 1 and goes[1][2] == 52, 'the runner runs')
local capped, freed = {}, {}
for _, call in ipairs(blendCalls) do
    if call[2] == 'max' then
        if call[3] == 3.0 then freed[call[1]] = true else capped[call[1]] = call[3] end
    end
end
assert(capped[50] == 1.0 and capped[51] == 1.0 and capped[54] == 1.0, 'walkers keep the walk cap')
assert(freed[52] and not capped[52], 'a runner owns its pace')
paceCalls = {}
HumalikeNpcPopulationClient.PaceTick()
local overridden = {}
for _, call in ipairs(paceCalls) do overridden[call[1]] = true end
assert(overridden[50] and overridden[51] and overridden[54] and not overridden[52],
    'the walk-rate override skips the runner')
assert(HumalikeNpcPopulationClient.Status().scenes == 2, 'two scenes are driven by this client')
reset()
taskRunning(51, FOLLOW, true)
netEntities[701] = 50
sceneBags[53] = scene({ id = 'sc-a', archetype = 'walk', slot = 2, leader_net = 701 })
HumalikeNpcPopulationClient.Tick(2000, false)
follows = named('follow')
assert(#follows == 1 and follows[1][2] == 53, 'a follower is configured again once its leader net id arrives')
reset()
heldBags[51] = true
HumalikeNpcPopulationClient.Tick(3000, false)
assert(calls[1][1] == 'clear' and calls[1][2] == 51 and calls[2][1] == 'stand' and calls[2][2] == 51,
    'the tick applies the hold flag')
heldBags[51] = nil
reset()
handlers['humalike:npc:populationState']({ enabled = true, cops_allowed = false, group_spawns = true })
assert(HumalikeNpcPopulationClient.Status().group_spawns == true and HumalikeNpcPopulationClient.Status().enabled)
handlers['humalike:npc:populationState']({ enabled = true, cops_allowed = false, group_spawns = false })
assert(HumalikeNpcPopulationClient.Status().group_spawns == false)
assert(HumalikeNpcPopulationClient.Reapply(51))
assert(calls[1][1] == 'clear' and calls[2][1] == 'follow', 'Reapply re-issues the scene task')
blendCalls = {}
HumalikeNpcPopulationClient.RestorePace(52)
assert(#blendCalls == 1 and blendCalls[1][1] == 52 and blendCalls[1][3] == 3.0,
    'RestorePace leaves a runner uncapped')
HumalikeNpcPopulationClient.RestorePace(51)
assert(#blendCalls == 2 and blendCalls[2][1] == 51 and blendCalls[2][3] == 1.0,
    'and caps a walker at its walk rate')
reset()
ragdoll[51] = true
fleeing[51] = true
HumalikeNpcPopulationClient.Tick(4000, false)
assert(#named('clear') == 0, 'a ragdolled fleeing scene ped is not cleared or re-tasked')
ragdoll[51] = nil
HumalikeNpcPopulationClient.Tick(5000, false)
assert(#named('clear') == 1 and named('clear')[1][2] == 51, 'once upright, the flee is replaced')
fleeing[51] = nil

print('client_scenes: ok')
