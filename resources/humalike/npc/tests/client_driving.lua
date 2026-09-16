function GetConvar(_name, default) return default end
dofile('config/shared.lua')

local handlers = {}
local threads = {}
local calls = {}
local pool = {}
local netEntities = {}
local inVehicle = {}
local seats = {}
local dead = {}
local ragdoll = {}
local taskStatus = {}
local players = {}
local ENTER, WANDER = 25, 32 -- GetHashKey stub = name length
local bags = {}

function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
function CreateThread(callback) threads[#threads + 1] = callback end
function GetCurrentResourceName() return 'humalike' end
function DoesEntityExist(entity) return pool[entity] == true end
function NetworkDoesEntityExistWithNetworkId(networkId) return netEntities[networkId] ~= nil end
function NetworkGetEntityFromNetworkId(networkId) return netEntities[networkId] or 0 end
function IsEntityDead(ped) return dead[ped] == true end
function IsPedRagdoll(ped) return ragdoll[ped] == true end
function IsPedInAnyVehicle(ped) return inVehicle[ped] ~= nil end
function IsPedInVehicle(ped, vehicle) return inVehicle[ped] == vehicle end
function GetPedInVehicleSeat(vehicle, seat) return seats[vehicle] and seats[vehicle][seat] or 0 end
function GetScriptTaskStatus(ped, hash) return taskStatus[ped] and taskStatus[ped][hash] or 7 end
function IsPedAPlayer(ped) return players[ped] == true end
function GetHashKey(name) return #name end
local function bagOf(ped)
    bags[ped] = bags[ped] or {}
    local bag = bags[ped]
    bag.set = bag.set or function(self, key, value) rawset(self, key, value) end
    return bag
end
function Entity(ped) return { state = bagOf(ped) } end
local function taskRunning(ped, hash, running)
    taskStatus[ped] = taskStatus[ped] or {}
    taskStatus[ped][hash] = running and 1 or 7
end
local function record(name)
    return function(...) calls[#calls + 1] = { name, ... } end
end
TaskWanderStandard = record('wander')
TaskVehicleTempAction = record('temp')
TaskEnterVehicle = record('enter')
TaskVehicleDriveWander = record('drive')
SetVehicleEngineOn = record('engine')
SetPedIntoVehicle = record('warp')
-- Entities stand far apart unless a test puts them together.
local coords = {}
local function vec(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, {
        __sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end,
        __len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end,
    })
end
function GetEntityCoords(entity)
    local c = coords[entity] or { x = entity * 100.0, y = 0, z = 0 }
    return vec(c.x, c.y, c.z)
end

dofile('client/driving.lua')
assert(#threads == 0)

local function named(name)
    local rows = {}
    for _, call in ipairs(calls) do
        if call[1] == name then rows[#rows + 1] = call end
    end
    return rows
end
local function last()
    return calls[#calls]
end
local function reset()
    calls = {}
end
local Driving = HumalikeNpcDriving
local driver = { humalike_body_behaviour = 'drive', humalike_vehicle_net = 601 }
for ped = 10, 30 do pool[ped] = true end
pool[40] = true
netEntities[601] = 40
bags[20] = driver

-- A seated driver starts the engine and drives once; the task is re-issued
-- only once it is gone, however long the vehicle stands at a light.
inVehicle[20] = 40
seats[40] = { [-1] = 20 }
assert(Driving.Apply(20, driver, 1000) == true)
assert(#calls == 2 and calls[1][1] == 'engine' and calls[1][2] == 40 and calls[1][3] == true)
assert(calls[2][1] == 'drive' and calls[2][2] == 20 and calls[2][3] == 40 and calls[2][4] == 12.0
    and calls[2][5] == 786603)
taskRunning(20, WANDER, true)
assert(Driving.Refresh(20, driver, 2000) == true)
assert(Driving.Refresh(20, driver, 60000) == true)
assert(#calls == 2, 'a driver with a live drive task is left alone')
taskRunning(20, WANDER, false)
assert(Driving.Refresh(20, driver, 61000) == true)
assert(#calls == 4 and calls[3][1] == 'engine' and last()[1] == 'drive', 'no drive task: drive again')
taskRunning(20, WANDER, true)

-- Told to drive off, the hold loop's repeat brake yields (the server's
-- release lands a tick later); an explicit stop order still brakes and ends
-- the yielding.
reset()
GetGameTimer = function() return 100000 end
GetVehiclePedIsIn = function(ped) return inVehicle[ped] or 0 end
assert(Driving.Brake(20) == true and last()[1] == 'temp', 'a held driver brakes')
reset()
assert(Driving.Resume(20) == true and last()[1] == 'drive')
reset()
assert(Driving.Brake(20) == true and #calls == 0, 'after Resume the loop brake is swallowed')
GetGameTimer = function() return 200000 end
assert(Driving.Brake(20) == true and #calls == 0, 'for as long as nobody orders a stop')
assert(Driving.Brake(20, true) == true and last()[1] == 'temp', 'a stop order brakes at once')
reset()
assert(Driving.Brake(20) == true and last()[1] == 'temp', 'and the loop brakes again from then on')
reset()

-- Reclaimed on foot beside its car (told to get back in), it WALKS: the
-- spawn-time warp is only for a driver born beside its car.
inVehicle[20] = nil
seats[40] = {}
coords[20] = { x = 1, y = 0, z = 1.5 }
coords[40] = { x = 0, y = 0, z = 0 }
Driving.Dismiss(20)
Driving.Reclaim(20)
assert(Driving.Apply(20, driver, 300000) == true and named('warp')[1] == nil and last()[1] == 'enter',
    'reclaimed: walks to the seat, no warp')
reset()
inVehicle[20] = 40
seats[40] = { [-1] = 20 }
assert(Driving.Apply(20, driver, 301000) == true and last()[1] == 'drive')
reset()
inVehicle[20] = nil
seats[40] = {}
assert(Driving.Apply(20, driver, 400000) == true and named('warp')[1] ~= nil, 'seated once, the warp is back for a spawn miss')
reset()
coords[20], coords[40] = nil, nil
inVehicle[20] = 40
seats[40] = { [-1] = 20 }
assert(Driving.Apply(20, driver, 401000) == true)
Driving.Forget({}) -- clean slate for the sections below
reset()
taskRunning(20, WANDER, true)

-- Lying on the roof (or standing by the door) of a free car: straight into
-- the seat and off it drives, no walk-and-open-the-door task.
reset()
inVehicle[20] = nil
seats[40] = {}
coords[20] = { x = 1, y = 0, z = 1.5 }
coords[40] = { x = 0, y = 0, z = 0 }
assert(Driving.Apply(20, driver, 60000) == true)
assert(calls[1][1] == 'warp' and calls[1][2] == 20 and calls[1][3] == 40 and calls[1][4] == -1,
    'an unseated driver beside its car is put in the seat')
assert(last()[1] == 'drive', 'and drives at once')
reset()
seats[40] = { [-1] = 99 }
coords[21] = { x = 1, y = 0, z = 1.5 }
assert(Driving.Apply(21, driver, 60000) == false and named('warp')[1] == nil
    and last()[1] == 'wander', 'never into a seat someone else holds: the body walks off')
seats[40] = {}
coords[20], coords[21], coords[40] = nil, nil, nil

-- Out of the vehicle: one enter attempt per window, never while the task runs.
reset()
inVehicle[20] = nil
seats[40] = {}
assert(Driving.Refresh(20, driver, 70000) == true)
assert(#calls == 1 and last()[1] == 'enter' and last()[2] == 20 and last()[3] == 40
    and last()[4] == 15000 and last()[5] == -1 and last()[6] == 1.0 and last()[7] == 1 and last()[8] == 0,
    'the driver re-enters the driver seat')
taskRunning(20, ENTER, true)
assert(Driving.Refresh(20, driver, 71000) == true)
assert(#calls == 1, 'not while the enter task runs')
taskRunning(20, ENTER, false)
assert(Driving.Refresh(20, driver, 72000) == true)
assert(Driving.Refresh(20, driver, 84000) == true)
assert(#calls == 1, 'a dropped enter task is not re-issued within 15 s of the last attempt')
assert(Driving.Refresh(20, driver, 85000) == true)
assert(#calls == 2 and last()[1] == 'enter', 'then once more')
assert(Driving.Apply(20, driver, 86000) == true)
assert(#calls == 2, 'Apply honours the window too')
inVehicle[20] = 40
seats[40] = { [-1] = 20 }
assert(Driving.Apply(20, driver, 87000) == true and last()[1] == 'drive', 'back in the seat: drive')

-- Moved over to a passenger seat of its own car (someone else drives): left
-- alone, never handed a drive task.
reset()
inVehicle[20] = 40
seats[40] = { [-1] = 99, [0] = 20 }
assert(Driving.Apply(20, driver, 89000) == true and #calls == 0, 'a passenger in its own car does not drive')
assert(Driving.Refresh(20, driver, 89500) == true and #calls == 0)
seats[40] = { [-1] = 20 }
reset()

-- Dismissed (got out on request, went with a player): on foot it is left to
-- the population's wander; seated in some other car it is left alone; back at
-- its own wheel it drives again.
reset()
inVehicle[20] = nil
seats[40] = {}
coords[20] = { x = 1, y = 0, z = 1.5 }
coords[40] = { x = 0, y = 0, z = 0 }
Driving.Dismiss(20)
assert(Driving.Apply(20, driver, 90000) == false and #calls == 0, 'dismissed: never warped or sent back in')
assert(driver.humalike_driver_dismissed == true, 'the dismissal rides on the ped for the next owner')
Driving.Forget({}) -- another client takes the ped over: no local memory, only the bag
assert(Driving.Apply(20, driver, 90500) == false and #calls == 0, 'the new owner honours the dismissal too')
assert(Driving.Refresh(20, driver, 91000) == false and #calls == 0)
inVehicle[20] = 99
assert(Driving.Refresh(20, driver, 92000) == true and #calls == 0, 'a passenger elsewhere is left alone')
inVehicle[20] = 40
seats[40] = { [-1] = 20 }
taskRunning(20, WANDER, false)
assert(Driving.Apply(20, driver, 93000) == true and last()[1] == 'drive', 'back at its own wheel: drives')
taskRunning(20, WANDER, true)
coords[20], coords[40] = nil, nil

-- Someone in the driver seat, or a player anywhere inside, ends the drive:
-- the body walks off once and is never sent back.
reset()
inVehicle[20] = nil
seats[40] = { [-1] = 21 }
assert(Driving.Refresh(20, driver, 100000) == false)
assert(#calls == 1 and last()[1] == 'wander' and last()[2] == 20, 'someone took the seat: walk off')
assert(Driving.Refresh(20, driver, 120000) == false and Driving.Apply(20, driver, 121000) == false)
assert(#calls == 1, 'and never sent back')
seats[40] = { [-1] = 20 }
inVehicle[20] = 40
taskRunning(20, WANDER, false)
assert(Driving.Refresh(20, driver, 122000) == true and last()[1] == 'drive',
    'seated again after all: the loss is forgiven')
taskRunning(20, WANDER, true)
reset()
inVehicle[20] = nil
seats[40] = { [0] = 1 }
players[1] = true
assert(Driving.Apply(20, driver, 130000) == false)
assert(#calls == 1 and last()[1] == 'wander', 'a player in the vehicle: the body walks')
assert(Driving.Refresh(20, driver, 150000) == false and #calls == 1)
players[1] = nil
seats[40] = {}
assert(Driving.Refresh(20, driver, 151000) == false, 'lost stays lost')
Driving.Forget({})
assert(Driving.Refresh(20, driver, 152000) == true and last()[1] == 'enter',
    'forgotten (the ped left the pool): a new life tries the seat again')
inVehicle[20] = 40
seats[40] = { [-1] = 20 }

-- No vehicle entity yet: a seated ped is left alone, one on foot is the
-- population's wanderer.
reset()
local orphan = { humalike_body_behaviour = 'drive', humalike_vehicle_net = 777 }
bags[22] = orphan
inVehicle[22] = 40
assert(Driving.Apply(22, orphan, 1000) == true and Driving.Refresh(22, orphan, 2000) == true)
inVehicle[22] = nil
assert(Driving.Apply(22, orphan, 3000) == false and Driving.Refresh(22, orphan, 4000) == false)
assert(#calls == 0, 'nothing is issued for a vehicle this client cannot see')

-- Brake: a seated driver brakes for a hold on itself; anyone else does not.
reset()
assert(Driving.Brake(20) == true)
assert(last()[1] == 'temp' and last()[2] == 20 and last()[3] == 40 and last()[4] == 27 and last()[5] == 2000)
bags[21] = { humalike_body_behaviour = 'wander' }
inVehicle[21] = 40
assert(Driving.Brake(21) == false, 'a walker in a car is not ours to brake')
seats[40] = { [-1] = 21, [0] = 20 }
assert(Driving.Brake(20) == false, 'a driver in the passenger seat has nothing to brake')
seats[40] = { [-1] = 20 }
inVehicle[20] = nil
assert(Driving.Brake(20) == false, 'a driver on foot stands like anyone')
inVehicle[20] = 40
assert(Driving.Brake(99) == false, 'a missing entity')
assert(#named('temp') == 1)

-- Only death and ragdoll incapacitate a driver; a seat never does.
assert(Driving.Incapacitated(20) == false)
ragdoll[20] = true
assert(Driving.Incapacitated(20) == true)
ragdoll[20] = nil
dead[20] = true
assert(Driving.Incapacitated(20) == true)
dead[20] = nil

-- A resource stop resets the attempt window.
reset()
inVehicle[20] = nil
seats[40] = {}
assert(Driving.Refresh(20, driver, 200000) == true and #calls == 1 and last()[1] == 'enter')
handlers['onResourceStop']('humalike')
assert(Driving.Refresh(20, driver, 201000) == true and #calls == 2 and last()[1] == 'enter')
inVehicle[20] = 40
seats[40] = { [-1] = 20 }

-- Wiring: the population tick hands drive bodies here, keeps them off the
-- walk cap and the per-frame move rate, and re-issues the drive on Reapply.
local sent
local kinds = {}
local bodyKinds = {}
local owned = {}
local blendCalls = {}
local paceCalls = {}
local clearCalls = {}
local stopped = {}
local visible = {}
local nodes = {}
local fleeing = {}
function TriggerServerEvent(...) sent = { ... } end
function PlayerPedId() return 1 end
coords[1] = { x = 0, y = 0, z = 0 } -- the player stands at the origin for the spawn-point checks
function IsSphereVisible(x) return visible[x] == true end
function GetSafeCoordForPed() return false, nil end
function IsAnyVehicleNearPoint() return false end
function GetClosestVehicleNodeWithHeading(x)
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
        humalike_body_behaviour = bags[ped] and bags[ped].humalike_body_behaviour,
        humalike_vehicle_net = bags[ped] and bags[ped].humalike_vehicle_net,
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
function IsPedFleeing(ped) return fleeing[ped] == true end
function IsPedUsingAnyScenario() return false end
function IsPedStopped(ped) return stopped[ped] == true end
function GetGameTimer() return 0 end
function GetActivePlayers() return {} end
function GetPlayerPed() return 0 end
function GetEntityPopulationType() return 7 end
function IsEntityAMissionEntity() return false end
function GetPedType() return 4 end
function SetEntityAsMissionEntity() end
function DeleteEntity() end
function ClearPedTasks(ped) clearCalls[#clearCalls + 1] = ped end
TaskStartScenarioInPlace = record('scenario')
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

pool = { [50] = true, [51] = true, [52] = true, [40] = true }
kinds = { [50] = 'population', [51] = 'population', [52] = 'population' }
bodyKinds = { [50] = 'persona', [51] = 'persona', [52] = 'persona' }
owned = { [50] = true, [51] = true, [52] = true }
bags[50] = driver
bags[52] = orphan -- seated in a vehicle this client cannot resolve yet
inVehicle[50] = 40
seats[40] = { [-1] = 50 }
inVehicle[52] = 40
stopped = { [50] = true, [51] = true, [52] = true }
reset()
blendCalls = {}
HumalikeNpcPopulationClient.Tick(1000, false)
local drives, wanders = named('drive'), named('wander')
assert(#drives == 1 and drives[1][2] == 50, 'the seated driver drives')
assert(#wanders == 1 and wanders[1][2] == 51, 'the body on foot wanders')
local capped, freed = {}, {}
for _, call in ipairs(blendCalls) do
    if call[2] == 'max' then
        if call[3] == 3.0 then freed[call[1]] = true else capped[call[1]] = call[3] end
    end
end
assert(capped[51] == 1.0 and not freed[51], 'a walker keeps the walk cap')
assert(freed[50] and freed[52] and not capped[50] and not capped[52], 'drivers own their pace')
paceCalls = {}
HumalikeNpcPopulationClient.PaceTick()
assert(#paceCalls == 1 and paceCalls[1][1] == 51, 'the move-rate override skips drivers')
assert(#named('wander') == 1, 'a seated driver without a visible vehicle (52) is left alone')
taskRunning(50, WANDER, true)
reset()
HumalikeNpcPopulationClient.Tick(2000, false)
HumalikeNpcPopulationClient.Tick(8000, false)
assert(#named('drive') == 0 and #named('wander') == 1, 'idle windows never re-task a seated driver')
taskRunning(50, WANDER, false)
HumalikeNpcPopulationClient.Tick(9000, false)
assert(#named('drive') == 1 and named('drive')[1][2] == 50, 'a dropped drive task is re-issued by the tick')
taskRunning(50, WANDER, true)

reset()
clearCalls = {}
assert(HumalikeNpcPopulationClient.Reapply(50))
assert(#clearCalls == 1 and clearCalls[1] == 50)
assert(#named('drive') == 1 and named('drive')[1][2] == 50, 'Reapply (a hold ended) drives again')
assert(blendCalls[#blendCalls][1] == 50 and blendCalls[#blendCalls][3] == 3.0, 'without a walk cap')
blendCalls = {}
HumalikeNpcPopulationClient.RestorePace(50)
assert(#blendCalls == 1 and blendCalls[1][3] == 3.0, 'RestorePace leaves a driver uncapped')
HumalikeNpcPopulationClient.Tick(10000, false)
assert(#blendCalls == 1, 'and the tick does not cap it either')

reset()
ragdoll[50] = true
fleeing[50] = true
HumalikeNpcPopulationClient.Tick(11000, false)
assert(#named('clear') == 0 and #named('drive') == 0, 'a ragdolled fleeing driver is left alone')
assert(not HumalikeNpcPopulationClient.Reapply(50), 'and not re-applied')
ragdoll[50] = nil
clearCalls = {}
HumalikeNpcPopulationClient.Tick(12000, false)
assert(#clearCalls == 1 and clearCalls[1] == 50 and #named('drive') == 1, 'upright: the flee is replaced by the drive')
fleeing[50] = nil

-- A driver whose vehicle vanished walks on the wander idle loop like anyone.
reset()
inVehicle[52] = nil
local function walked()
    local peds = {}
    for _, call in ipairs(named('wander')) do peds[call[2]] = true end
    return peds
end
HumalikeNpcPopulationClient.Tick(20000, false)
assert(not walked()[52], 'the idle window applies first')
HumalikeNpcPopulationClient.Tick(26000, false)
assert(walked()[52] and not walked()[50], 'on foot with no vehicle: wander; the seated driver stays put')


print('client_driving: ok')
