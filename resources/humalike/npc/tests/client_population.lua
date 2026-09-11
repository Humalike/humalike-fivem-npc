function GetConvar(_name, default) return default end
dofile('config/shared.lua')

local handlers = {}
local threads = {}
local sent
local visible = {}
local safeCoords = {}
local groundZ = {}
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
function CreateThread(callback) threads[#threads + 1] = callback end
function TriggerServerEvent(...) sent = { ... } end
function PlayerPedId() return 1 end
function DoesEntityExist(entity) return entity == 1 or pool[entity] ~= nil end
function GetEntityCoords(entity) return coords[entity] or { x = 0, y = 0, z = 0 } end
function GetSafeCoordForPed(x, y, z)
    local safe = safeCoords[x]
    if safe then return true, safe end
    return false, nil
end
function GetGroundZFor_3dCoord(x)
    if groundZ[x] then return true, groundZ[x] end
    return false, 0
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
function HumalikeAmbientControlHeldPed(ped) return heldPeds[ped] == true end
function DownedNpcOf(ped) return downedPeds[ped] end
function GetCurrentResourceName() return 'humalike' end
function GetGameTimer() return nowMs end
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

dofile('client/population.lua')
assert(#threads == 2, 'one density thread and one pool walk')

local candidates = {
    { x = 100, y = 0, z = 10, heading = 90 },
    { x = 10, y = 0, z = 10, heading = 45 },
    { x = 200, y = 0, z = 10, heading = 180 },
    { x = 300, y = 0, z = 10 },
}
visible[100] = true
safeCoords[200] = { x = 202, y = 1, z = 11 }
local point = HumalikeNpcPopulationClient.SelectSpawnPoint(candidates)
assert(point.x == 202 and point.y == 1 and point.z == 11 and point.heading == 180,
    'visible and near candidates are rejected')

safeCoords[200] = nil
visible[200] = true
groundZ[300] = 12.5
point = HumalikeNpcPopulationClient.SelectSpawnPoint(candidates)
assert(point.x == 300 and point.z == 12.5 and point.heading == 0.0,
    'ground z fallback applies when no safe coordinate exists')

groundZ[300] = nil
point = HumalikeNpcPopulationClient.SelectSpawnPoint(candidates)
assert(point.x == 300 and point.z == 10, 'raw candidate z is the last fallback')

visible[300] = true
assert(HumalikeNpcPopulationClient.SelectSpawnPoint(candidates) == nil)
assert(HumalikeNpcPopulationClient.SelectSpawnPoint({ { x = 'a', y = 0, z = 0 } }) == nil)
assert(HumalikeNpcPopulationClient.SelectSpawnPoint(nil) == nil)

visible[300] = nil
handlers['humalike:npc:populationSpawnPoint']('req-1', candidates)
assert(sent[1] == 'humalike:npc:populationSpawnPointResult')
assert(sent[2] == 'req-1' and sent[3].x == 300)
sent = nil
handlers['humalike:npc:populationSpawnPoint'](7, candidates)
assert(sent == nil, 'a non-string request id is ignored')
visible[300] = true
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

HumalikeNpcPopulationClient.Tick(1000, false)
assert(#wanderCalls == 2 and wanderCalls[1] == 20 and wanderCalls[2] == 26,
    'first ownership sends unmanaged wander bodies wandering at once')
assert(#blendCalls == 7, 'only unmanaged bodies get the walk cap')
assert(blendCalls[1][1] == 20 and blendCalls[1][2] == 'min' and blendCalls[1][3] == 0.0)
assert(blendCalls[2][1] == 20 and blendCalls[2][2] == 'max' and blendCalls[2][3] == 0.75)
assert(blendCalls[3][1] == 22 and blendCalls[3][3] == 3.0 and blendCalls[4][1] == 23
    and blendCalls[4][3] == 3.0 and blendCalls[5][1] == 24 and blendCalls[5][3] == 3.0,
    'a managed body has any earlier local cap lifted on ownership')
assert(blendCalls[7][1] == 26 and blendCalls[7][3] == 1.0, 'walk_rate defaults to 1.0')
HumalikeNpcPopulationClient.Tick(3000, false)
assert(#wanderCalls == 2 and #blendCalls == 7, 'a stopped ped is not re-tasked before the idle window')
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
bodyKinds = { [30] = 'extra', [31] = 'extra' }
seeds = { [30] = 4242 }
owned = { [30] = true, [31] = true, [32] = true }
stopped = {}
HumalikeNpcPopulationClient.Tick(50000, false)
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

pool = { [40] = true, [41] = true, [42] = true, [43] = true }
kinds = { [40] = 'population', [41] = 'population', [42] = 'population', [43] = 'population' }
bodyKinds = {}
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
HumalikeNpcPopulationClient.Tick(302000, false)
assert(#blendCalls == 4 and #applied == 2, 'a new body behind the same handle is configured again')

print('client_population: ok')
