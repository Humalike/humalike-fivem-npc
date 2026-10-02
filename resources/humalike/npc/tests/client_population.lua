function GetConvar(_name, default) return default end
dofile('config/convars.lua')
dofile('config/shared.lua')

local handlers = {}
local threads = {}
local sent
local visible = {}
local safeCoords = {}
local pool = {}
local kinds = {}
local npcIds = {}
local owned = {}
local stopped = {}
local dead = {}
local scenario = {}
local actionControlled = {}
local heldPeds = {}
local downedPeds = {}
local wanderCalls = {}
local bodyKinds = {}
local seeds = {}
local applied = {}
local copCalls = {}
local densityCalls = {}
local behaviours = {}
local scenarios = {}
local walkRates = {}
local blendCalls = {}
local scenarioCalls = {}
local coords = {}
local populationTypes = {}
local missionEntities = {}
local inVehicle = {}
local missionMarks = {}
local deleted = {}
local pedTypes = {}
local activePlayers = {}
local playerPeds = {}
local clearCalls = {}
local controlled = {}
local nowMs = 0

function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
local bagHandlers = {}
function AddStateBagChangeHandler(key, _, handler) bagHandlers[key] = handler end
function GetEntityFromStateBagName(name) return tonumber(name:match('^entity:(%d+)$')) - 1000 end
function NetworkGetNetworkIdFromEntity(ped) return ped + 1000 end
-- A body streaming in: its kind bag reaches the client.
local function announce(ped) bagHandlers.humalike_npc_kind(('entity:%d'):format(ped + 1000), 'humalike_npc_kind', 'population') end
function CreateThread(callback) threads[#threads + 1] = callback end
function TriggerServerEvent(...) sent = { ... } end
function PlayerPedId() return 1 end
function DoesEntityExist(entity) return entity == 1 or pool[entity] ~= nil end
function GetEntityCoords(entity) return coords[entity] or { x = 0, y = 0, z = 0 } end
local safeFlags = {}
function GetSafeCoordForPed(x, y, z, onlyOnPavement, flags)
    safeFlags[#safeFlags + 1] = { onlyOnPavement, flags }
    local safe = safeCoords[x]
    if safe then return true, safe end
    return false, nil
end
function IsSphereVisible(x) return visible[x] == true end
function GetGamePool()
    local peds = {}
    for ped in pairs(pool) do peds[#peds + 1] = ped end
    table.sort(peds)
    return peds
end
function IsPedAPlayer(ped) return ped == 1 end
function Entity(ped)
    return { state = {
        humalike_npc_kind = kinds[ped],
        humalike_npc_id = npcIds[ped],
        humalike_body_kind = bodyKinds[ped],
        humalike_style_seed = seeds[ped],
        humalike_body_behaviour = behaviours[ped],
        humalike_body_scenario = scenarios[ped],
        humalike_walk_rate = walkRates[ped],
    } }
end
function SetCreateRandomCops(enabled) copCalls[#copCalls + 1] = enabled end
function SetCreateRandomCopsNotOnScenarios(enabled) copCalls[#copCalls + 1] = enabled end
function SetCreateRandomCopsOnScenarios(enabled) copCalls[#copCalls + 1] = enabled end
function SetPedDensityMultiplierThisFrame(value)
    densityCalls[#densityCalls + 1] = { 'ped', value }
end
function SetScenarioPedDensityMultiplierThisFrame(value, other)
    densityCalls[#densityCalls + 1] = { 'scenario', value, other }
end
HumalikeNpcStyle = {
    ApplySeed = function(ped, seed)
        applied[#applied + 1] = { ped, seed }
        return seed ~= nil
    end,
}
function NetworkHasControlOfEntity(ped) return owned[ped] == true end
function IsEntityDead(ped) return dead[ped] == true end
function IsPedRagdoll() return false end
local blockingCalls = {}
function SetBlockingOfNonTemporaryEvents(ped, blocked)
    blockingCalls[#blockingCalls + 1] = { ped, 'ped', blocked }
end
function TaskSetBlockingOfNonTemporaryEvents(ped, blocked)
    blockingCalls[#blockingCalls + 1] = { ped, 'task', blocked }
end
function IsPedInAnyVehicle(ped) return inVehicle[ped] == true end
function IsPedUsingAnyScenario(ped) return scenario[ped] == true end
function IsPedStopped(ped) return stopped[ped] == true end
function TaskWanderStandard(ped) wanderCalls[#wanderCalls + 1] = ped end
function TaskStartScenarioInPlace(ped, name, delay, play)
    scenarioCalls[#scenarioCalls + 1] = { ped, name, delay, play }
end
function SetPedMinMoveBlendRatio(ped, value) blendCalls[#blendCalls + 1] = { ped, 'min', value } end
function SetPedMaxMoveBlendRatio(ped, value) blendCalls[#blendCalls + 1] = { ped, 'max', value } end
function GetEntityPopulationType(ped) return populationTypes[ped] or 7 end
function IsEntityAMissionEntity(ped) return missionEntities[ped] == true end
function SetEntityAsMissionEntity(ped) missionMarks[#missionMarks + 1] = ped end
function DeleteEntity(ped)
    deleted[#deleted + 1] = ped
    pool[ped] = nil
end
function IsActionControlled(ped) return actionControlled[ped] == true end
local paceCalls = {}
function SetPedMoveRateOverride(ped, rate) paceCalls[#paceCalls + 1] = { ped, rate } end
function HumalikeAmbientControlHeldPed(ped) return heldPeds[ped] == true end
function DownedNpcOf(ped) return downedPeds[ped] end
function GetCurrentResourceName() return 'humalike' end
function GetGameTimer() return nowMs end
local fleeing = {}
function IsPedFleeing(ped) return fleeing[ped] == true end
function GetPedType(ped) return pedTypes[ped] or 4 end
function GetActivePlayers() return activePlayers end
function GetPlayerPed(playerId) return playerPeds[playerId] or 0 end
function ClearPedTasks(ped) clearCalls[#clearCalls + 1] = ped end
HumalikeNpcRuntimeControl = {
    IsControlled = function(npcId, domain)
        local held = controlled[npcId]
        return held ~= nil and (held.all == true or held[domain] == true)
    end,
}

dofile('client/reactions.lua')
dofile('client/population.lua')
assert(#threads == 2, 'one per-frame thread (density + pace) and one body tick')
assert(bagHandlers.humalike_npc_kind and bagHandlers.humalike_body_id and bagHandlers.humalike_walk_rate,
    'bodies announce themselves through their bags')
Config.Population.MoveRate = 0.82 -- the ambling rate, to exercise the per-frame loop

local candidates = {
    { x = 100, y = 0, z = 10, heading = 90 },
    { x = 10, y = 0, z = 10, heading = 45 },
    { x = 200, y = 0, z = 10, heading = 180 },
    { x = 300, y = 0, z = 10 },
}
safeCoords[100] = { x = 100, y = 0, z = 10 }
visible[100] = true
safeCoords[10] = { x = 10, y = 0, z = 10 }
safeCoords[200] = { x = 202, y = 1, z = 11 }
local point = HumalikeNpcPopulationClient.SelectSpawnPoint(candidates)
assert(point.x == 100 and point.y == 0 and point.z == 10 and point.heading == 90,
    'a point in the player\'s sight is fine; only distance is checked')
safeCoords[100] = nil
point = HumalikeNpcPopulationClient.SelectSpawnPoint(candidates)
assert(point.x == 202 and point.y == 1 and point.z == 11 and point.heading == 180,
    'near candidates are rejected')
safeCoords[10] = nil

for _, call in ipairs(safeFlags) do
    assert(call[1] == true and call[2] == 14,
        'pavement, connected, outdoors, dry: flags 2|4|8')
end

safeCoords[200] = nil
visible[200] = true
safeCoords[300] = { x = 301, y = 2, z = 12.5 }
point = HumalikeNpcPopulationClient.SelectSpawnPoint(candidates)
assert(point.x == 301 and point.z == 12.5 and point.heading == 0.0,
    'a candidate with no pavement is skipped')

safeCoords[300] = nil
assert(HumalikeNpcPopulationClient.SelectSpawnPoint(candidates) == nil,
    'no pavement anywhere means no spawn point')

safeCoords[300] = { x = 301, y = 2, z = 12.5 }
visible[301] = true
assert(HumalikeNpcPopulationClient.SelectSpawnPoint(candidates).x == 301,
    'a pavement point in the player\'s sight is still a spawn point')
assert(HumalikeNpcPopulationClient.SelectSpawnPoint({ { x = 'a', y = 0, z = 0 } }) == nil)
assert(HumalikeNpcPopulationClient.SelectSpawnPoint(nil) == nil)

visible[301] = nil
local nodes = {}
function GetClosestVehicleNodeWithHeading(x, y, z, nodeType, zTolerance, flags)
    assert(nodeType == 1 and zTolerance == 3.0 and flags == 0, 'road nodes only')
    local node = nodes[x]
    if node then return true, { x = node[1], y = node[2], z = node[3] }, node[4] end
    return false, nil, 0.0
end
local occupiedNodes = {}
function IsAnyVehicleNearPoint(x, y, z, radius)
    assert(radius == Config.Population.VehicleNodeClearance)
    return occupiedNodes[x] == true
end
nodes[10] = { 12, 1, 10.5, 270 }
nodes[300] = { 305, 2, 12, 135 }
point = HumalikeNpcPopulationClient.SelectSpawnPoint(candidates, 'vehicle')
assert(point.x == 305 and point.y == 2 and point.z == 12 and point.heading == 135,
    'vehicle mode picks the road node with its heading; a node too near the player is skipped')
occupiedNodes[305] = true
assert(HumalikeNpcPopulationClient.SelectSpawnPoint(candidates, 'vehicle') == nil,
    'a road node already holding a vehicle is never a spawn point')
occupiedNodes[305] = nil
nodes[300] = { 305, 2, 12 }
point = HumalikeNpcPopulationClient.SelectSpawnPoint(candidates, 'vehicle')
assert(point.heading == 0.0, 'a node without a heading falls back to the candidate heading')
nodes[300] = nil
assert(HumalikeNpcPopulationClient.SelectSpawnPoint(candidates, 'vehicle') == nil,
    'no acceptable road node means no spawn point; pavement is never used for a vehicle')
handlers['humalike:npc:populationSpawnPoint']('req-v', candidates, 'vehicle')
assert(sent[2] == 'req-v' and sent[3] == nil)
handlers['humalike:npc:populationSpawnPoint']('req-1', candidates)
assert(sent[1] == 'humalike:npc:populationSpawnPointResult')
assert(sent[2] == 'req-1' and sent[3].x == 301, 'the pavement point, not the road node')
sent = nil
handlers['humalike:npc:populationSpawnPoint'](7, candidates)
assert(sent == nil, 'a non-string request id is ignored')
safeCoords[300] = nil
handlers['humalike:npc:populationSpawnPoint']('req-2', candidates)
assert(sent[2] == 'req-2' and sent[3] == nil, 'no acceptable point replies nil')

pool = { [20] = true, [21] = true, [22] = true, [23] = true, [24] = true, [25] = true, [26] = true }
kinds = { [20] = 'population', [21] = 'population', [22] = 'population', [23] = 'population',
    [24] = 'population', [25] = 'persistent', [26] = 'population' }
owned = { [20] = true, [22] = true, [23] = true, [24] = true, [25] = true, [26] = true }
stopped = { [20] = true, [21] = true, [22] = true, [23] = true, [24] = true, [25] = true,
    [26] = true }
actionControlled[22] = true
heldPeds[23] = true
downedPeds[24] = 'wounded'
walkRates[20] = 0.75
bodyKinds = { [20] = 'persona', [21] = 'persona', [22] = 'persona', [23] = 'persona',
    [24] = 'persona', [26] = 'persona' }

HumalikeNpcPopulationClient.Tick(1000, false)
HumalikeNpcPopulationClient.PaceTick()
assert(#paceCalls == 2, 'only the bodies nobody else drives amble')
for _, call in ipairs(paceCalls) do
    assert(call[2] == 0.82 and (call[1] == 20 or call[1] == 26),
        'the ambling rate, never on a managed body')
end
paceCalls = {}
heldPeds[20] = true
HumalikeNpcPopulationClient.PaceTick()
assert(#paceCalls == 2, 'the per-frame loop does no lookups of its own; a hold is announced')
paceCalls = {}
HumalikeNpcPopulationClient.RefreshPace(20)
HumalikeNpcPopulationClient.PaceTick()
assert(#paceCalls == 1 and paceCalls[1][1] == 26, 'a hold that began after the last tick stops the override')
heldPeds[20] = nil
npcIds[26] = 'npc-26'
AmbientPedNpcIds = { [26] = 'npc-26' } -- the lease module indexes npc ids by ped
controlled['npc-26'] = { movement = true }
paceCalls = {}
HumalikeNpcPopulationClient.RebuildPace()
HumalikeNpcPopulationClient.PaceTick()
assert(#paceCalls == 1 and paceCalls[1][1] == 20, 'so does a runtime-control movement lease')
controlled['npc-26'] = nil
npcIds[26] = nil
AmbientPedNpcIds = {}
owned[26] = false
paceCalls = {}
HumalikeNpcPopulationClient.RefreshPace(26)
HumalikeNpcPopulationClient.PaceTick()
assert(#paceCalls == 1 and paceCalls[1][1] == 20, 'and a body no longer under this client\'s control')
owned[26] = true
HumalikeNpcPopulationClient.RebuildPace()
paceCalls = {}
assert(#wanderCalls == 2 and wanderCalls[1] == 20 and wanderCalls[2] == 26,
    'first ownership sends unmanaged wander bodies wandering at once')
local function blockingCounts(from)
    local flags, tasks = {}, {}
    for index = from or 1, #blockingCalls do
        local call = blockingCalls[index]
        assert(call[3] == true, 'reactions are blocked, never released')
        local bucket = call[2] == 'ped' and flags or tasks
        bucket[call[1]] = (bucket[call[1]] or 0) + 1
    end
    return flags, tasks
end
local flags, tasks = blockingCounts()
for _, ped in ipairs({ 20, 22, 23, 24, 26 }) do
    assert(flags[ped] == 1, 'every owned persona body has its reactions flagged off')
end
assert(tasks[20] == 1 and tasks[26] == 1, 'the blocking task is issued once on first ownership')
assert(tasks[22] == nil and tasks[23] == nil and tasks[24] == nil,
    'never on a ped an action, hold or wound is driving')
assert(flags[25] == nil and tasks[25] == nil, 'a persistent ped is not ours')
assert(HumalikeNpcPopulationClient.OwnsReactions(20) == true)
assert(HumalikeNpcPopulationClient.OwnsReactions(25) == false,
    'a persistent ped is not ours to own here')
assert(HumalikeNpcPopulationClient.OwnsReactions(99) == false, 'a missing entity owns nothing')
assert(#blendCalls == 7, 'only unmanaged bodies get the walk cap')
assert(blendCalls[1][1] == 20 and blendCalls[1][2] == 'min' and blendCalls[1][3] == 0.0)
assert(blendCalls[2][1] == 20 and blendCalls[2][2] == 'max' and blendCalls[2][3] == 0.75)
assert(blendCalls[3][1] == 22 and blendCalls[3][3] == 3.0 and blendCalls[4][1] == 23
    and blendCalls[4][3] == 3.0 and blendCalls[5][1] == 24 and blendCalls[5][3] == 3.0,
    'a managed body has any earlier local cap lifted on ownership')
assert(blendCalls[7][1] == 26 and blendCalls[7][3] == 1.0, 'walk_rate defaults to 1.0')
HumalikeNpcPopulationClient.Tick(3000, false)
assert(#wanderCalls == 2 and #blendCalls == 7, 'a stopped ped is not re-tasked before the idle window')
flags, tasks = blockingCounts(8)
assert(#blockingCalls == 12 and next(tasks) == nil, 'the flag is re-asserted on every owned tick')
for _, ped in ipairs({ 20, 22, 23, 24, 26 }) do
    assert(flags[ped] == 1, 'never the task again')
end
HumalikeNpcPopulationClient.Tick(6000, false)
assert(#wanderCalls == 4 and wanderCalls[3] == 20 and wanderCalls[4] == 26,
    'only owned, idle, unmanaged population peds wander again')
HumalikeNpcPopulationClient.Tick(7000, false)
assert(#wanderCalls == 4, 'a freshly tasked ped waits for another idle window')
HumalikeNpcPopulationClient.Tick(11000, false)
assert(#wanderCalls == 6)

stopped[20] = false
HumalikeNpcPopulationClient.Tick(16000, false)
assert(#wanderCalls == 7 and wanderCalls[7] == 26, 'a moving ped resets its idle clock')
stopped[20] = true
HumalikeNpcPopulationClient.Tick(17000, false)
assert(#wanderCalls == 7)
HumalikeNpcPopulationClient.Tick(22000, false)
assert(#wanderCalls == 9)

dead[26] = true
scenario[20] = true
HumalikeNpcPopulationClient.Tick(28000, false)
assert(#wanderCalls == 9, 'dead peds and scenario users are left alone')

owned[21] = true
HumalikeNpcPopulationClient.Tick(29000, false)
assert(#wanderCalls == 10 and wanderCalls[10] == 21, 'a ped newly owned after migration is configured')
HumalikeNpcPopulationClient.Tick(34000, false)
assert(#wanderCalls == 11 and wanderCalls[11] == 21)

handlers['onResourceStop']('humalike')
HumalikeNpcPopulationClient.Tick(35000, false)
assert(#wanderCalls == 13 and wanderCalls[12] == 20 and wanderCalls[13] == 21,
    'bodies are reconfigured after a stop; a dead one is not tasked')
HumalikeNpcPopulationClient.Tick(36000, false)
local before = #wanderCalls
HumalikeNpcPopulationClient.Tick(40000, false)
assert(#wanderCalls == before + 1, 'idle clocks restart after a resource stop')

pool = { [30] = true, [31] = true, [32] = true }
kinds = { [30] = 'population', [31] = 'population', [32] = 'population' }
bodyKinds = { [30] = 'extra', [31] = 'extra', [32] = 'persona' }
seeds = { [30] = 4242 }
owned = { [30] = true, [31] = true, [32] = true }
stopped = {}
local blockedBefore = #blockingCalls
HumalikeNpcPopulationClient.Tick(50000, false)
local blockedPeds = {}
for index = blockedBefore + 1, #blockingCalls do blockedPeds[blockingCalls[index][1]] = true end
assert(blockedPeds[32] and not blockedPeds[30] and not blockedPeds[31],
    'only persona bodies are blocked; extras keep GTA reactions')
assert(HumalikeNpcPopulationClient.OwnsReactions(32) == true)
assert(HumalikeNpcPopulationClient.OwnsReactions(30) == false, 'an extra is not ours to own')
assert(#applied == 2 and applied[1][1] == 30 and applied[1][2] == 4242,
    'extras are dressed from their seed; persona bodies are not')
assert(applied[2][1] == 31 and applied[2][2] == nil)
HumalikeNpcPopulationClient.Tick(51000, false)
assert(#applied == 3 and applied[3][1] == 31, 'a dressed extra stays dressed; a seedless one retries')
owned[30] = false
HumalikeNpcPopulationClient.Tick(52000, false)
assert(#applied == 4 and applied[4][1] == 31, 'an unowned extra is left alone')
owned[30] = true
HumalikeNpcPopulationClient.Tick(53000, false)
assert(#applied == 6 and applied[5][1] == 30 and applied[5][2] == 4242,
    'an extra is dressed again once ownership returns')
assert(applied[6][1] == 31)
pool[33] = true
kinds[33] = 'population'
owned[33] = true
announce(33)
blockedBefore = #blockingCalls
local wanderBefore = #wanderCalls
HumalikeNpcPopulationClient.Tick(54000, false)
assert(#blockingCalls == blockedBefore + 1 and blockingCalls[#blockingCalls][1] == 32
    and #wanderCalls == wanderBefore, 'a body whose kind has not replicated is not ready: skipped')
assert(HumalikeNpcPopulationClient.OwnsReactions(33) == false)
bodyKinds[33] = 'persona'
bagHandlers.humalike_body_kind('entity:1033', 'humalike_body_kind', 'persona')
HumalikeNpcPopulationClient.Tick(55000, false)
assert(#wanderCalls == wanderBefore + 1 and wanderCalls[#wanderCalls] == 33,
    'and configured as soon as the bag says persona')
pool[33], kinds[33], owned[33], bodyKinds[33] = nil, nil, nil, nil

pool = { [40] = true, [41] = true, [42] = true, [43] = true }
kinds = { [40] = 'population', [41] = 'population', [42] = 'population', [43] = 'population' }
bodyKinds = { [40] = 'persona', [41] = 'persona', [42] = 'persona', [43] = 'persona' }
owned = { [40] = true, [41] = true, [42] = true, [43] = true }
behaviours = { [40] = 'stand', [41] = 'scenario', [42] = 'wander', [43] = 'scenario' }
scenarios = { [41] = 'WORLD_HUMAN_SMOKING', [43] = 'WORLD_HUMAN_DRINKING' }
walkRates = { [41] = 0.8, [42] = 0.7, [43] = 1.4 }
heldPeds[43] = true
stopped = { [40] = true, [41] = true, [42] = true, [43] = true }
scenario = {}
wanderCalls, blendCalls, scenarioCalls = {}, {}, {}
HumalikeNpcPopulationClient.Tick(60000, false)
assert(#wanderCalls == 1 and wanderCalls[1] == 42, 'only the wander body walks')
assert(#scenarioCalls == 2, 'stand and scenario bodies start a scenario in place')
assert(scenarioCalls[1][1] == 40 and scenarioCalls[1][2] == 'WORLD_HUMAN_STAND_IMPATIENT'
    and scenarioCalls[1][3] == 0 and scenarioCalls[1][4] == true, 'stand defaults its scenario')
assert(scenarioCalls[2][1] == 41 and scenarioCalls[2][2] == 'WORLD_HUMAN_SMOKING')
assert(#blendCalls == 7, 'the held body is not capped; its pace is lifted for the hold')
assert(blendCalls[4][1] == 41 and blendCalls[4][3] == 0.8)
assert(blendCalls[6][1] == 42 and blendCalls[6][3] == 0.7)
assert(blendCalls[7][1] == 43 and blendCalls[7][3] == 3.0)
assert(blendCalls[1][1] == 40 and blendCalls[1][3] == 0.0 and blendCalls[2][3] == 1.0)

scenario[41] = true
HumalikeNpcPopulationClient.Tick(66000, false)
assert(#wanderCalls == 2 and wanderCalls[2] == 42, 'the wander body re-tasks after 5 s idle')
assert(#scenarioCalls == 2, 'scenario bodies are not re-tasked before 10 s out of scenario')
HumalikeNpcPopulationClient.Tick(70000, false)
assert(#scenarioCalls == 3 and scenarioCalls[3][1] == 40, 'a stand body out of scenario for 10 s restarts')
assert(#wanderCalls == 2, 'a stand body never wanders on the idle loop')
HumalikeNpcPopulationClient.Tick(81000, false)
assert(#scenarioCalls == 4 and scenarioCalls[4][1] == 40)
heldPeds[43] = false
HumalikeNpcPopulationClient.Tick(82000, false)
assert(#scenarioCalls == 4, 'the wander tick does not re-task a released body')
assert(#blendCalls == 9 and blendCalls[9][1] == 43 and blendCalls[9][3] == 1.0,
    'the walk cap returns once the hold ends, clamped to 1.0')
HumalikeNpcPopulationClient.Tick(92000, false)
assert(#scenarioCalls == 6 and scenarioCalls[5][1] == 40)
assert(scenarioCalls[6][1] == 43 and scenarioCalls[6][2] == 'WORLD_HUMAN_DRINKING',
    'a released body restarts its own scenario when idle')
scenario[41] = false
HumalikeNpcPopulationClient.Tick(93000, false)
assert(#scenarioCalls == 6)
HumalikeNpcPopulationClient.Tick(103000, false)
assert(#scenarioCalls == 9 and scenarioCalls[7][1] == 40 and scenarioCalls[9][1] == 43)
assert(scenarioCalls[8][1] == 41 and scenarioCalls[8][2] == 'WORLD_HUMAN_SMOKING',
    'a scenario body that left its scenario for 10 s restarts it')
stopped[40] = false
HumalikeNpcPopulationClient.Tick(104000, false)
HumalikeNpcPopulationClient.Tick(115000, false)
assert(#scenarioCalls == 11 and scenarioCalls[10][1] == 41 and scenarioCalls[11][1] == 43,
    'a moving stand body is not pulled back into its scenario')
stopped[40] = true
HumalikeNpcPopulationClient.Tick(116000, false)
HumalikeNpcPopulationClient.Tick(125000, false)
assert(#scenarioCalls == 13 and scenarioCalls[12][1] == 41 and scenarioCalls[13][1] == 43,
    'the scenario clock only starts once the body has stopped')
HumalikeNpcPopulationClient.Tick(126000, false)
assert(#scenarioCalls == 14 and scenarioCalls[14][1] == 40)

local function sendState(active, allowCops)
    handlers['humalike:npc:populationState']({ enabled = active, cops_allowed = allowCops })
end
assert(not HumalikeNpcPopulationClient.DensityTick() and #densityCalls == 0)
assert(HumalikeNpcPopulationClient.SetState('bogus') == false)
assert(not HumalikeNpcPopulationClient.DensityTick())
handlers['humalike:npc:populationState']('on')
assert(not HumalikeNpcPopulationClient.DensityTick(), 'a non-table payload is ignored')
sendState(false, false)
assert(not HumalikeNpcPopulationClient.DensityTick())
assert(not HumalikeNpcPopulationClient.DensityTick() and #copCalls == 0,
    'a disabled state leaves GTA pedestrians and cops alone')
sendState(true, false)
assert(HumalikeNpcPopulationClient.DensityTick())
assert(densityCalls[1][1] == 'ped' and densityCalls[1][2] == 0.0)
assert(densityCalls[2][1] == 'scenario' and densityCalls[2][2] == 0.0 and densityCalls[2][3] == 0.0)
assert(#copCalls == 3 and copCalls[1] == false and copCalls[2] == false and copCalls[3] == false)
sendState(true, false)
assert(#copCalls == 3, 'cops are switched off once per enable')
sendState(false, false)
assert(#copCalls == 6 and copCalls[4] == true and copCalls[5] == true and copCalls[6] == true)
assert(not HumalikeNpcPopulationClient.DensityTick())
sendState(true, true)
assert(#copCalls == 6, 'the server-side cops setting keeps random cops')
sendState(false, true)
assert(#copCalls == 6, 'nothing to restore when we never turned them off')
sendState(true, false)
assert(#copCalls == 9 and copCalls[9] == false)
sendState(true, true)
assert(#copCalls == 12 and copCalls[12] == true, 'allowing cops while enabled restores them')
sendState(true, false)
assert(#copCalls == 15 and copCalls[15] == false)
handlers['onResourceStop']('humalike')
assert(#copCalls == 18 and copCalls[18] == true, 'a resource stop restores random cops')
handlers['onResourceStop']('humalike')
assert(#copCalls == 18)

pool = { [50] = true, [51] = true, [52] = true, [53] = true, [54] = true, [55] = true,
    [56] = true, [57] = true, [58] = true, [59] = true, [60] = true, [61] = true, [62] = true }
kinds = { [55] = 'population' }
npcIds = { [56] = 'external-npc' }
owned = { [50] = true, [51] = true, [52] = true, [53] = true, [54] = true, [55] = true,
    [56] = true, [58] = true, [59] = true, [60] = true, [61] = true, [62] = true }
populationTypes = { [50] = 5, [51] = 7, [52] = 4, [53] = 5, [54] = 5, [55] = 5, [56] = 5,
    [57] = 5, [58] = 4, [59] = 5, [60] = 4, [61] = 5, [62] = 5 }
missionEntities = { [52] = true }
inVehicle = { [54] = true }
for ped = 50, 62 do coords[ped] = { x = 100, y = 0, z = 0 } end
coords[53] = { x = 10, y = 0, z = 0 }
assert(HumalikeNpcPopulationClient.DensityTick())
assert(HumalikeNpcPopulationClient.Tick(nowMs, true) == 5, 'at most five leftovers per sweep')
assert(#deleted == 5 and #missionMarks == 5)
assert(deleted[1] == 50 and deleted[2] == 58 and deleted[3] == 59 and deleted[4] == 60
    and deleted[5] == 61, 'mission, near, in-vehicle, humalike and unowned peds survive')
assert(missionMarks[1] == 50, 'a leftover becomes a mission entity before deletion')
assert(HumalikeNpcPopulationClient.Tick(nowMs, true) == 1 and deleted[6] == 62)
assert(HumalikeNpcPopulationClient.Tick(nowMs, true) == 0)
assert(pool[51] and pool[52] and pool[53] and pool[54] and pool[55] and pool[56] and pool[57])
pool[63] = true
owned[63] = true
populationTypes[63] = 5
coords[63] = { x = 0, y = 0, z = 15 }
assert(HumalikeNpcPopulationClient.Tick(nowMs, true) == 0, 'exactly 15 m away is still too close')
coords[63] = { x = 0, y = 0, z = 15.1 }
sendState(false, false)
assert(HumalikeNpcPopulationClient.Tick(nowMs, true) == 0, 'the sweep is off while disabled')
sendState(true, false)
assert(HumalikeNpcPopulationClient.Tick(nowMs, true) == 1 and deleted[7] == 63)

pool[64] = true
owned[64] = true
populationTypes[64] = 5
coords[64] = { x = 500, y = 0, z = 0 }
activePlayers = { 2 }
playerPeds[2] = 90
pool[90] = true
coords[90] = { x = 505, y = 0, z = 0 }
assert(HumalikeNpcPopulationClient.Tick(nowMs, true) == 0, 'a ped next to another player survives')
coords[90] = { x = 600, y = 0, z = 0 }
assert(HumalikeNpcPopulationClient.Tick(nowMs, true) == 1 and deleted[8] == 64)
activePlayers = {}

pool[65], owned[65], populationTypes[65], pedTypes[65] = true, true, 5, 6
pool[66], owned[66], populationTypes[66], pedTypes[66] = true, true, 5, 27
pool[67], owned[67], populationTypes[67], pedTypes[67] = true, true, 5, 4
for ped = 65, 67 do coords[ped] = { x = 700, y = 0, z = 0 } end
sendState(true, true)
assert(HumalikeNpcPopulationClient.Tick(nowMs, true) == 1 and deleted[9] == 67, 'cop and swat are kept')
sendState(true, false)
assert(HumalikeNpcPopulationClient.Tick(nowMs, true) == 2 and deleted[10] == 65 and deleted[11] == 66,
    'without the convar cops are leftovers like anyone else')

pool = { [70] = true, [71] = true, [72] = true }
kinds = { [70] = 'population', [71] = 'population', [72] = 'population' }
bodyKinds = { [70] = 'persona', [71] = 'persona', [72] = 'persona' }
owned = { [70] = true, [71] = true, [72] = true }
walkRates = { [70] = 0.6, [71] = 0.9 }
npcIds = { [71] = 'npc-71' }
stopped = {}
actionControlled = { [70] = true }
controlled['npc-71'] = { movement = true }
blendCalls, wanderCalls = {}, {}
HumalikeNpcPopulationClient.Tick(200000, false)
local capped, freed = {}, {}
for _, call in ipairs(blendCalls) do
    if call[2] == 'max' then
        if call[3] == 3.0 then freed[call[1]] = true else capped[call[1]] = call[3] end
    end
end
assert(capped[72] == 1.0 and not freed[72], 'the unmanaged body is capped')
assert(freed[70] and freed[71] and not capped[70] and not capped[71],
    'configure lifts the cap on a managed body')
assert(#wanderCalls == 1 and wanderCalls[1] == 72, 'a runtime-controlled body is not re-tasked')
controlled['npc-71'] = { all = true }
blendCalls = {}
HumalikeNpcPopulationClient.Tick(200500, false)
assert(#blendCalls == 0, 'an all-domain lease counts as movement')
controlled['npc-71'] = nil
HumalikeNpcPopulationClient.Tick(201000, false)
assert(#blendCalls == 2 and blendCalls[2][1] == 71 and blendCalls[2][3] == 0.9,
    'the cap comes back on the next tick once the lease ends')
HumalikeNpcPopulationClient.Tick(201500, false)
assert(#blendCalls == 2, 'and is not repeated while nothing changes')
controlled['npc-71'] = { movement = true }
HumalikeNpcPopulationClient.Tick(202000, false)
assert(#blendCalls == 3 and blendCalls[3][1] == 71 and blendCalls[3][3] == 3.0,
    'a lease acquired while owned lifts the cap on the next tick')
HumalikeNpcPopulationClient.Tick(202500, false)
assert(#blendCalls == 3, 'once')
controlled['npc-71'] = nil
HumalikeNpcPopulationClient.Tick(203000, false)
assert(#blendCalls == 5 and blendCalls[5][1] == 71 and blendCalls[5][3] == 0.9, 'and the cap returns')
HumalikeNpcPopulationClient.OwnPace(70)
assert(blendCalls[6][1] == 70 and blendCalls[6][2] == 'max' and blendCalls[6][3] == 3.0,
    'OwnPace lifts the cap to the engine default')
actionControlled[70] = nil
HumalikeNpcPopulationClient.RestorePace(70)
assert(blendCalls[7][1] == 70 and blendCalls[7][3] == 0.6, 'RestorePace clamps to the planned walk rate')
HumalikeNpcPopulationClient.Tick(204000, false)
assert(#blendCalls == 7, 'a restored body is not capped again by the tick')
pool[73] = true
kinds[73] = 'persistent'
HumalikeNpcPopulationClient.RestorePace(73)
assert(blendCalls[8][1] == 73 and blendCalls[8][3] == 3.0, 'anything but a population body gets 3.0')
walkRates[72] = nil
HumalikeNpcPopulationClient.RestorePace(72)
assert(blendCalls[9][1] == 72 and blendCalls[9][3] == 3.0, 'a population body without a walk rate too')
HumalikeNpcPopulationClient.RestorePace(999)
assert(#blendCalls == 9, 'a missing entity is ignored')

walkRates[72] = 0.7
bagHandlers.humalike_walk_rate('entity:1072', 'humalike_walk_rate', 0.7)
blendCalls = {}
HumalikeNpcPopulationClient.Tick(205000, false)
assert(#blendCalls == 2 and blendCalls[2][1] == 72 and blendCalls[2][3] == 0.7,
    'a body restored to 3.0 is capped again by the tick')
HumalikeNpcPopulationClient.Tick(205500, false)
assert(#blendCalls == 2, 'once')
owned[72] = false
HumalikeNpcPopulationClient.Tick(206000, false)
owned[72] = true
HumalikeNpcPopulationClient.Tick(207000, false)
assert(#blendCalls == 4 and blendCalls[4][1] == 72 and blendCalls[4][3] == 0.7,
    'ownership regained: the walk cap is set again')
owned[72] = false
HumalikeNpcPopulationClient.Tick(208000, false)
actionControlled[72] = true
owned[72] = true
HumalikeNpcPopulationClient.Tick(209000, false)
assert(#blendCalls == 5 and blendCalls[5][1] == 72 and blendCalls[5][3] == 3.0,
    'regained mid-action: the old local cap is lifted for the action')
actionControlled[72] = nil
HumalikeNpcPopulationClient.RestorePace(72)

fleeing[72] = true
wanderCalls, clearCalls = {}, {}
HumalikeNpcPopulationClient.Tick(203000, false)
assert(#clearCalls == 1 and clearCalls[1] == 72 and #wanderCalls == 1 and wanderCalls[1] == 72,
    'a fleeing persona body is re-tasked with its planned behaviour')
fleeing[72] = nil
HumalikeNpcPopulationClient.Tick(204000, false)
assert(#clearCalls == 1, 'only while it flees')
bodyKinds[72] = 'extra'
bagHandlers.humalike_body_kind('entity:1072', 'humalike_body_kind', 'extra')
fleeing[72] = true
HumalikeNpcPopulationClient.Tick(205000, false)
assert(#clearCalls == 1, 'an extra keeps GTA brain, its flee is its own')
bodyKinds[72] = 'persona'
bagHandlers.humalike_body_kind('entity:1072', 'humalike_body_kind', 'persona')
fleeing[72] = nil
clearCalls = {}

behaviours[71] = 'scenario'
scenarios[71] = 'WORLD_HUMAN_SMOKING'
scenarioCalls = {}
heldPeds[71] = true
assert(not HumalikeNpcPopulationClient.Reapply(71), 'a held body is left to its hold')
heldPeds[71] = false
assert(HumalikeNpcPopulationClient.Reapply(71))
assert(#clearCalls == 1 and clearCalls[1] == 71)
assert(#scenarioCalls == 1 and scenarioCalls[1][1] == 71 and scenarioCalls[1][2] == 'WORLD_HUMAN_SMOKING')
assert(blendCalls[#blendCalls][1] == 71 and blendCalls[#blendCalls][3] == 0.9)
owned[71] = false
assert(not HumalikeNpcPopulationClient.Reapply(71), 'only the owner re-tasks')
assert(not HumalikeNpcPopulationClient.Reapply(73), 'and only population bodies')

pool = { [80] = true }
kinds = { [80] = 'population' }
owned = { [80] = true }
bodyKinds = { [80] = 'extra' }
seeds = { [80] = 1 }
walkRates = {}
stopped = {}
local bodyIdOf = { [80] = 'body-a' }
local previousEntity = Entity
function Entity(ped)
    local entity = previousEntity(ped)
    entity.state.humalike_body_id = bodyIdOf[ped]
    return entity
end
blendCalls, applied = {}, {}
HumalikeNpcPopulationClient.Tick(300000, false)
HumalikeNpcPopulationClient.Tick(301000, false)
assert(#blendCalls == 2 and #applied == 1, 'a known handle is configured and dressed once')
bodyIdOf[80] = 'body-b'
bagHandlers.humalike_body_id('entity:1080', 'humalike_body_id', 'body-b')
HumalikeNpcPopulationClient.Tick(302000, false)
assert(#blendCalls == 4 and #applied == 2, 'a new body behind the same handle is configured again')

pool = { [90] = true, [91] = true, [92] = true, [93] = true, [94] = true }
kinds = { [90] = 'population', [91] = 'population' }
bodyKinds = { [90] = 'persona', [91] = 'extra' }
owned = { [90] = true, [91] = true, [92] = true, [93] = true, [94] = true }
populationTypes = { [92] = 4, [93] = 5, [94] = 7 }
bodyIdOf, stopped, seeds = {}, {}, {}
local entityReads = 0
local countedEntity = Entity
function Entity(ped)
    entityReads = entityReads + 1
    return countedEntity(ped)
end
HumalikeNpcPopulationClient.Tick(400000, true)
assert(entityReads == 7, 'a pool pass reads one bag per ped, a second (the snapshot) for our bodies')
assert(HumalikeNpcPopulationClient.Count() == 2, 'and remembers the two bodies it found')
entityReads = 0
HumalikeNpcPopulationClient.Tick(400500, false)
assert(entityReads == 0, 'a body tick reads no bag at all: the snapshot is kept per body')
HumalikeNpcPopulationClient.Tick(405000, false)
assert(entityReads == 0, 'a pool pass is not due for another ten seconds')
entityReads = 0
HumalikeNpcPopulationClient.SetState(true, false)
HumalikeNpcPopulationClient.Tick(401000, true)
assert(entityReads == 3, 'a sweep reads every ped it does not know; known bodies cost nothing')
HumalikeNpcPopulationClient.SetState(false, false)
paceCalls = {}
HumalikeNpcPopulationClient.PaceTick()
assert(#paceCalls == 2, 'both walkers amble')
entityReads = 0
for _ = 1, 60 do HumalikeNpcPopulationClient.PaceTick() end
assert(entityReads == 0, 'the per-frame loop never touches a bag')
Config.Population.MoveRate = 1.0
paceCalls = {}
assert(HumalikeNpcPopulationClient.PaceTick() == false and #paceCalls == 0,
    'at the game\'s own rate the per-frame loop does nothing')
Config.Population.MoveRate = 0.82

-- A body announced by its bag joins the next tick without a pool pass.
pool[96], kinds[96], bodyKinds[96], owned[96] = true, 'population', 'persona', true
entityReads = 0
announce(96)
assert(entityReads == 1 and HumalikeNpcPopulationClient.Count() == 3, 'one snapshot read on announcement')
function GetGamePool() error('no pool pass between sweeps') end
wanderCalls = {}
HumalikeNpcPopulationClient.Tick(402000, false)
assert(#wanderCalls == 1 and wanderCalls[1] == 96, 'the announced body is configured on the next tick')
pool[96], owned[96] = nil, nil
HumalikeNpcPopulationClient.Tick(403000, false)
assert(HumalikeNpcPopulationClient.Count() == 2, 'a deleted body is forgotten')
function GetGamePool()
    local peds = {}
    for ped in pairs(pool) do peds[#peds + 1] = ped end
    table.sort(peds)
    return peds
end

-- A sliced pass spreads the pool over frames and swaps its lists in only at the end.
pool[95], kinds[95], bodyKinds[95], owned[95] = true, 'population', 'persona', true
local frames = 0
function Wait(ms)
    assert(ms == 0, 'a slice waits one frame')
    frames = frames + 1
    coroutine.yield()
end
local slicedPass = coroutine.create(function()
    return HumalikeNpcPopulationClient.SlicedTick(500000, true, 3)
end)
assert(coroutine.resume(slicedPass))
paceCalls = {}
HumalikeNpcPopulationClient.PaceTick()
assert(#paceCalls == 2, 'the previous lists stay in force while the pass runs')
heldPeds[90] = true
HumalikeNpcPopulationClient.RefreshPace(90)
assert(coroutine.resume(slicedPass))
assert(coroutine.resume(slicedPass))
assert(coroutine.status(slicedPass) == 'dead' and frames == 2, 'two known bodies and six pool peds in three slices')
paceCalls = {}
HumalikeNpcPopulationClient.PaceTick()
assert(#paceCalls == 2, 'the new walker joins once the pass completes')
for _, call in ipairs(paceCalls) do
    assert(call[1] == 91 or call[1] == 95, 'a hold announced mid-pass is not undone by the swap')
end
heldPeds[90] = nil

print('client_population: ok')
