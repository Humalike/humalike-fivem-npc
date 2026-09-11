HumalikeNpcPopulationClient = HumalikeNpcPopulationClient or {}
local stoppedSince = {}
local scenarioIdleSince = {}
local configured = {}
local dressed = {}
local paced = {}
local enabled = false
local copsAllowed = false
local copsDisabled = false
local lastSweepAt = 0
local DEFAULT_STAND_SCENARIO = 'WORLD_HUMAN_STAND_IMPATIENT'
local FREE_PACE = 3.0 -- max move blend ratio, sprint

local function config()
    return Config.Population
end

local function groundPoint(candidate)
    local found, safe = GetSafeCoordForPed(candidate.x, candidate.y, candidate.z, true, 16)
    if found and safe then return safe.x, safe.y, safe.z end
    local grounded, groundZ = GetGroundZFor_3dCoord(candidate.x, candidate.y,
        candidate.z + 1.0, false)
    return candidate.x, candidate.y, grounded and groundZ or candidate.z
end

local function acceptable(x, y, z)
    local playerPed = PlayerPedId()
    if playerPed == 0 or not DoesEntityExist(playerPed) then return false end
    local coords = GetEntityCoords(playerPed)
    local dx, dy, dz = coords.x - x, coords.y - y, coords.z - z
    local minDistance = config().MinPlayerDistance
    if dx * dx + dy * dy + dz * dz < minDistance * minDistance then return false end
    return not IsSphereVisible(x, y, z, 2.0)
end

function HumalikeNpcPopulationClient.SelectSpawnPoint(candidates)
    for _, candidate in ipairs(type(candidates) == 'table' and candidates or {}) do
        if type(candidate) == 'table' and HumalikeValidCoordinate(candidate.x)
            and HumalikeValidCoordinate(candidate.y) and HumalikeValidCoordinate(candidate.z) then
            local x, y, z = groundPoint(candidate)
            if acceptable(x, y, z) then
                return { x = x, y = y, z = z, heading = tonumber(candidate.heading) or 0.0 }
            end
        end
    end
    return nil
end

RegisterNetEvent('humalike:npc:populationSpawnPoint')
AddEventHandler('humalike:npc:populationSpawnPoint', function(requestId, candidates)
    if type(requestId) ~= 'string' then return end
    TriggerServerEvent('humalike:npc:populationSpawnPointResult', requestId,
        HumalikeNpcPopulationClient.SelectSpawnPoint(candidates))
end)

local function setRandomCops(enabled)
    SetCreateRandomCops(enabled)
    SetCreateRandomCopsNotOnScenarios(enabled)
    SetCreateRandomCopsOnScenarios(enabled)
end

local function applyRandomCops()
    local suppress = enabled and not copsAllowed
    if suppress and not copsDisabled then
        setRandomCops(false)
        copsDisabled = true
    elseif not suppress and copsDisabled then
        setRandomCops(true)
        copsDisabled = false
    end
end

function HumalikeNpcPopulationClient.SetState(active, allowCops)
    active = active == true
    allowCops = allowCops == true
    if active == enabled and allowCops == copsAllowed then return false end
    enabled, copsAllowed = active, allowCops
    applyRandomCops()
    return true
end

function HumalikeNpcPopulationClient.DensityTick()
    if not enabled then return false end
    SetPedDensityMultiplierThisFrame(0.0)
    SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
    return true
end

RegisterNetEvent('humalike:npc:populationState')
AddEventHandler('humalike:npc:populationState', function(payload)
    if type(payload) ~= 'table' then return end
    HumalikeNpcPopulationClient.SetState(payload.enabled, payload.cops_allowed)
end)

CreateThread(function()
    while true do
        Wait(HumalikeNpcPopulationClient.DensityTick() and 0 or 500)
    end
end)

local function managed(ped)
    if IsActionControlled and IsActionControlled(ped) then return true end
    if HumalikeAmbientControlHeldPed and HumalikeAmbientControlHeldPed(ped) then return true end
    if DownedNpcOf and DownedNpcOf(ped) then return true end
    local npcId = Entity(ped).state.humalike_npc_id
    if npcId and HumalikeNpcRuntimeControl
        and HumalikeNpcRuntimeControl.IsControlled(npcId, 'movement') then return true end
    return false
end

local function incapacitated(ped)
    return IsEntityDead(ped) or IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, false)
end

local function wanderIdle(ped, now)
    if incapacitated(ped) or IsPedUsingAnyScenario(ped) or not IsPedStopped(ped) then
        stoppedSince[ped] = nil
        return false
    end
    stoppedSince[ped] = stoppedSince[ped] or now
    return now - stoppedSince[ped] >= config().WanderIdleMs
end

local function scenarioIdle(ped, now)
    if incapacitated(ped) or IsPedUsingAnyScenario(ped) or not IsPedStopped(ped) then
        scenarioIdleSince[ped] = nil
        return false
    end
    scenarioIdleSince[ped] = scenarioIdleSince[ped] or now
    return now - scenarioIdleSince[ped] >= config().ScenarioIdleMs
end

local function behaviourOf(state)
    local behaviour = state.humalike_body_behaviour
    if behaviour ~= 'stand' and behaviour ~= 'scenario' then return 'wander' end
    return behaviour
end

local function scenarioOf(state)
    local name = state.humalike_body_scenario
    if type(name) == 'string' and name ~= '' then return name end
    return DEFAULT_STAND_SCENARIO
end

local function walkRate(state)
    local rate = tonumber(state.humalike_walk_rate)
    if not rate then return nil end
    return math.max(0.5, math.min(1.0, rate))
end

-- The wander loop caps the pace only while nothing else drives the ped.
local function capPace(ped, state)
    paced[ped] = true
    SetPedMinMoveBlendRatio(ped, 0.0)
    SetPedMaxMoveBlendRatio(ped, walkRate(state) or 1.0)
end

function HumalikeNpcPopulationClient.OwnPace(ped)
    if not DoesEntityExist(ped) then return end
    paced[ped] = nil
    SetPedMaxMoveBlendRatio(ped, FREE_PACE)
end

function HumalikeNpcPopulationClient.RestorePace(ped)
    if not DoesEntityExist(ped) then return end
    local state = Entity(ped).state
    local rate = state.humalike_npc_kind == 'population' and walkRate(state) or nil
    if rate then
        paced[ped] = true
        SetPedMaxMoveBlendRatio(ped, rate)
    else
        paced[ped] = nil
        SetPedMaxMoveBlendRatio(ped, FREE_PACE)
    end
end

local function applyBehaviour(ped, state, now)
    if behaviourOf(state) == 'wander' then
        stoppedSince[ped] = now
        TaskWanderStandard(ped, 10.0, 10)
        return
    end
    scenarioIdleSince[ped] = now
    TaskStartScenarioInPlace(ped, scenarioOf(state), 0, true)
end

local function hasMind(state)
    return state.humalike_body_kind == 'persona'
end

-- Extras keep GTA's reactions; a persona body's mind decides for it.
local function ownReactions(ped, state, withTask)
    if not hasMind(state) then return end
    HumalikeNpcReactions.Own(ped, withTask)
end

function HumalikeNpcPopulationClient.OwnsReactions(ped)
    if not DoesEntityExist(ped) then return false end
    local state = Entity(ped).state
    return state.humalike_npc_kind == 'population' and hasMind(state)
end

local function configure(ped, state, now)
    configured[ped] = state.humalike_body_id or true
    local isManaged = managed(ped)
    ownReactions(ped, state, not isManaged)
    if isManaged then
        HumalikeNpcPopulationClient.OwnPace(ped)
        return
    end
    capPace(ped, state)
    if not incapacitated(ped) then applyBehaviour(ped, state, now) end
end

local function refresh(ped, state, now)
    -- A release or a migration may have handed the reactions back to GTA.
    ownReactions(ped, state, false)
    if managed(ped) then
        if paced[ped] then HumalikeNpcPopulationClient.OwnPace(ped) end
        return
    end
    if not paced[ped] then capPace(ped, state) end
    -- A flee GTA started before the flag came back is replaced by the plan.
    if hasMind(state) and IsPedFleeing(ped) then
        ClearPedTasks(ped)
        applyBehaviour(ped, state, now)
        return
    end
    local idle
    if behaviourOf(state) == 'wander' then
        idle = wanderIdle(ped, now)
    else
        idle = scenarioIdle(ped, now)
    end
    if idle then applyBehaviour(ped, state, now) end
end

function HumalikeNpcPopulationClient.Reapply(ped)
    if not DoesEntityExist(ped) or not NetworkHasControlOfEntity(ped) then return false end
    local state = Entity(ped).state
    if state.humalike_npc_kind ~= 'population' or managed(ped) or incapacitated(ped) then
        return false
    end
    ClearPedTasks(ped)
    capPace(ped, state)
    applyBehaviour(ped, state, GetGameTimer())
    return true
end

local function dress(ped, state)
    if state.humalike_body_kind ~= 'extra' or not HumalikeNpcStyle then return end
    if dressed[ped] == (state.humalike_body_id or true) then return end
    if HumalikeNpcStyle.ApplySeed(ped, state.humalike_style_seed) then
        dressed[ped] = state.humalike_body_id or true
    end
end

local function forgetUnseen(registry, seen)
    for ped in pairs(registry) do
        if not seen[ped] then registry[ped] = nil end
    end
end

local function playerPeds()
    local peds = {}
    local localPed = PlayerPedId()
    if localPed ~= 0 and DoesEntityExist(localPed) then peds[#peds + 1] = localPed end
    for _, playerId in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(playerId)
        if ped ~= 0 and ped ~= localPed and DoesEntityExist(ped) then peds[#peds + 1] = ped end
    end
    return peds
end

local function nearAnyPlayer(coords, players, minDistance)
    for _, playerPed in ipairs(players) do
        local other = GetEntityCoords(playerPed)
        local dx, dy, dz = other.x - coords.x, other.y - coords.y, other.z - coords.z
        if dx * dx + dy * dy + dz * dz <= minDistance * minDistance then return true end
    end
    return false
end

local function gtaLeftover(ped, state, players)
    if state.humalike_npc_kind ~= nil or state.humalike_npc_id ~= nil then return false end
    local cfg = config()
    if not cfg.GtaPopulationTypes[GetEntityPopulationType(ped)] or IsPedInAnyVehicle(ped, false)
        or IsEntityAMissionEntity(ped) then return false end
    if copsAllowed and cfg.CopPedTypes[GetPedType(ped)] then return false end
    return not nearAnyPlayer(GetEntityCoords(ped), players, cfg.SweepMinPlayerDistance)
end

function HumalikeNpcPopulationClient.Tick(now, sweep)
    local seen = {}
    local cfg = config()
    local removed = 0
    sweep = sweep and enabled
    local players = sweep and playerPeds() or nil
    for _, ped in ipairs(GetGamePool('CPed')) do
        if DoesEntityExist(ped) and not IsPedAPlayer(ped) and NetworkHasControlOfEntity(ped) then
            local state = Entity(ped).state
            if state.humalike_npc_kind == 'population' and state.humalike_body_kind == nil then
                seen[ped] = true -- kind not replicated yet; leave it alone this tick
            elseif state.humalike_npc_kind == 'population' then
                seen[ped] = true
                dress(ped, state)
                if configured[ped] == (state.humalike_body_id or true) then
                    refresh(ped, state, now)
                else
                    configure(ped, state, now)
                end
            elseif sweep and removed < cfg.SweepMaxPerTick and gtaLeftover(ped, state, players) then
                SetEntityAsMissionEntity(ped, true, true)
                DeleteEntity(ped)
                removed = removed + 1
            end
        end
    end
    forgetUnseen(stoppedSince, seen)
    forgetUnseen(scenarioIdleSince, seen)
    forgetUnseen(configured, seen)
    forgetUnseen(dressed, seen)
    forgetUnseen(paced, seen)
    return removed
end

CreateThread(function()
    while true do
        Wait(config().WanderTickMs)
        local now = GetGameTimer()
        local sweep = enabled and now - lastSweepAt >= config().SweepTickMs
        if sweep then lastSweepAt = now end
        HumalikeNpcPopulationClient.Tick(now, sweep)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    stoppedSince, scenarioIdleSince, configured, dressed, paced = {}, {}, {}, {}, {}
    if copsDisabled then
        setRandomCops(true)
        copsDisabled = false
    end
end)
