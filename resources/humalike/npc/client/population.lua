HumalikeNpcPopulationClient = HumalikeNpcPopulationClient or {}
local stoppedSince = {}
local scenarioIdleSince = {}
local configured = {}
local dressed = {}
local paced = {}
-- Every population body this client knows of: ped -> { netId, state }. Bodies
-- announce themselves through their state bags as they stream in; a pool
-- pass every SweepTickMs catches what a bag missed and sweeps GTA leftovers.
local bodies = {}
local ownedBodies = {}
local paceSet = {} -- walkers this client drives right now; the per-frame loop touches only these
-- The pass in progress: it walks the bodies (and the ped pool, when due) in
-- slices, and the lists it builds replace ownedBodies/paceSet only at the end.
local currentPass = nil
local enabled = false
local copsAllowed = false
local copsDisabled = false
local lastScanAt = -math.huge
local scanRequested = false
local DEFAULT_STAND_SCENARIO = 'WORLD_HUMAN_STAND_IMPATIENT'
local FREE_PACE = 3.0 -- max move blend ratio, sprint
local BODY_KEYS = {
    'humalike_npc_kind', 'humalike_npc_id', 'humalike_body_kind', 'humalike_body_id',
    'humalike_body_behaviour', 'humalike_body_scenario', 'humalike_walk_rate',
    'humalike_style_seed', 'humalike_vehicle_net',
}
local BODY_KEY = {}
for _, key in ipairs(BODY_KEYS) do BODY_KEY[key] = true end

local function config()
    return Config.Population
end

-- One read per key, absent keys included. Keys outside the list, and `:set`,
-- reach the live bag. A body's bags are written once, at spawn, so the
-- snapshot is kept per body and refreshed from the change handlers.
local function snapshot(ped)
    local live = Entity(ped).state
    local state = {}
    for _, key in ipairs(BODY_KEYS) do state[key] = live[key] end
    return setmetatable(state, { __index = function(_, key)
        if BODY_KEY[key] then return nil end
        return live[key]
    end })
end

-- The ambient lease module keeps the npc id of each leased ped; the bag
-- copy is the fallback where that index is missing.
local function npcIdOf(ped, state)
    local index = AmbientPedNpcIds
    local npcId = index and index[ped] or nil
    if npcId ~= nil then return npcId end
    return state and state.humalike_npc_id or nil
end

-- GetSafeCoordForPed: 2 not isolated, 4 not interior, 8 not water.
-- onlyOnPavement = true already sets flag 1.
local PAVEMENT_FLAGS = 2 | 4 | 8

local function pavementPoint(candidate)
    local found, safe = GetSafeCoordForPed(candidate.x, candidate.y, candidate.z, true,
        PAVEMENT_FLAGS)
    if found and safe then return safe.x, safe.y, safe.z end
    return nil
end

-- Node type 1 (roads) with a heading, so a vehicle lands facing the traffic.
-- Neighbouring candidates snap to the same node, so a node already holding a
-- vehicle (ours or traffic) is skipped rather than spawned into.
local function roadPoint(candidate)
    local found, node, heading = GetClosestVehicleNodeWithHeading(candidate.x, candidate.y,
        candidate.z, 1, 3.0, 0)
    if not found or not node then return nil end
    if IsAnyVehicleNearPoint(node.x, node.y, node.z, config().VehicleNodeClearance) then
        return nil
    end
    return node.x, node.y, node.z, heading
end

local function acceptable(x, y, z)
    local playerPed = PlayerPedId()
    if playerPed == 0 or not DoesEntityExist(playerPed) then return false end
    local coords = GetEntityCoords(playerPed)
    local dx, dy, dz = coords.x - x, coords.y - y, coords.z - z
    local minDistance = config().MinPlayerDistance
    return dx * dx + dy * dy + dz * dz >= minDistance * minDistance
end

-- `mode` is `foot` (pavement, the default) or `vehicle` (nearest road node).
function HumalikeNpcPopulationClient.SelectSpawnPoint(candidates, mode)
    local onRoad = mode == 'vehicle'
    for _, candidate in ipairs(type(candidates) == 'table' and candidates or {}) do
        if type(candidate) == 'table' and HumalikeValidCoordinate(candidate.x)
            and HumalikeValidCoordinate(candidate.y) and HumalikeValidCoordinate(candidate.z) then
            local x, y, z, heading
            if onRoad then
                x, y, z, heading = roadPoint(candidate)
            else
                x, y, z = pavementPoint(candidate)
            end
            if x and acceptable(x, y, z) then
                return { x = x, y = y, z = z,
                    heading = tonumber(heading) or tonumber(candidate.heading) or 0.0 }
            end
        end
    end
    return nil
end

RegisterNetEvent('humalike:npc:populationSpawnPoint')
AddEventHandler('humalike:npc:populationSpawnPoint', function(requestId, candidates, mode)
    if type(requestId) ~= 'string' then return end
    TriggerServerEvent('humalike:npc:populationSpawnPointResult', requestId,
        HumalikeNpcPopulationClient.SelectSpawnPoint(candidates, mode))
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
    if active and not enabled then scanRequested = true end -- sweep the street at once
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

-- `state` is a snapshot; its npc id is passed on so nobody re-reads the bag.
local function managed(ped, state)
    if IsActionControlled and IsActionControlled(ped) then return true end
    local npcId = npcIdOf(ped, state) or false
    if HumalikeAmbientControlHeldPed and HumalikeAmbientControlHeldPed(ped, npcId) then return true end
    if DownedNpcOf and DownedNpcOf(ped, npcId) then return true end
    if npcId and HumalikeNpcRuntimeControl
        and HumalikeNpcRuntimeControl.IsControlled(npcId, 'movement') then return true end
    return false
end

local function behaviourOf(state)
    local behaviour = state.humalike_body_behaviour
    if behaviour ~= 'stand' and behaviour ~= 'scenario' and behaviour ~= 'drive' then
        return 'wander'
    end
    return behaviour
end

local function drives(state)
    return behaviourOf(state) == 'drive'
end

-- A driver belongs in a vehicle; for anyone else a seat means someone took over.
local function incapacitated(ped, state)
    if state and drives(state) then return HumalikeNpcDriving.Incapacitated(ped) end
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

-- A takeover hook during a sliced pass also corrects the pass's own list
-- for a body it already visited, so the swap does not bring back a stale entry.
local function setPacing(ped, value)
    paceSet[ped] = value
    if currentPass and currentPass.walkers[ped] ~= nil then currentPass.pacing[ped] = value end
end

function HumalikeNpcPopulationClient.OwnPace(ped)
    setPacing(ped, nil)
    if not DoesEntityExist(ped) then return end
    paced[ped] = nil
    SetPedMaxMoveBlendRatio(ped, FREE_PACE)
end

-- Drivers own their pace; every other body ambles at its walk rate.
local function pace(ped, state)
    if drives(state) then
        HumalikeNpcPopulationClient.OwnPace(ped)
    else
        capPace(ped, state)
    end
end

-- The cached bags of a known body, else a fresh read.
local function stateOf(ped)
    local body = bodies[ped]
    if body then return body.state end
    return snapshot(ped)
end

-- Whether the per-frame move-rate override applies to this body right now.
-- Called when a hold, wound, action or lease starts or ends; the tick redoes it every second.
function HumalikeNpcPopulationClient.RefreshPace(ped)
    local walking = ownedBodies[ped] or (currentPass and currentPass.walkers[ped])
    if not walking or not DoesEntityExist(ped) or not NetworkHasControlOfEntity(ped) then
        setPacing(ped, nil)
        return false
    end
    local applies = not managed(ped, stateOf(ped))
    setPacing(ped, applies or nil)
    return applies
end

function HumalikeNpcPopulationClient.RebuildPace()
    paceSet = {}
    for ped in pairs(ownedBodies) do HumalikeNpcPopulationClient.RefreshPace(ped) end
    if currentPass then
        for ped in pairs(currentPass.walkers) do HumalikeNpcPopulationClient.RefreshPace(ped) end
    end
end

function HumalikeNpcPopulationClient.RestorePace(ped)
    if not DoesEntityExist(ped) then return end
    local state = snapshot(ped)
    local rate = state.humalike_npc_kind == 'population' and not drives(state)
        and walkRate(state) or nil
    if rate then
        paced[ped] = true
        SetPedMaxMoveBlendRatio(ped, rate)
    else
        paced[ped] = nil
        SetPedMaxMoveBlendRatio(ped, FREE_PACE)
    end
    HumalikeNpcPopulationClient.RefreshPace(ped)
end

-- A driver without its vehicle walks like a wanderer until the edge culls it.
local function applyBehaviour(ped, state, now)
    local behaviour = behaviourOf(state)
    if behaviour == 'drive' and HumalikeNpcDriving.Apply(ped, state, now) then return end
    if behaviour == 'wander' or behaviour == 'drive' then
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
    local state = snapshot(ped)
    return state.humalike_npc_kind == 'population' and hasMind(state)
end

local function configure(ped, state, now, isManaged)
    configured[ped] = state.humalike_body_id or true
    ownReactions(ped, state, not isManaged)
    if isManaged then
        HumalikeNpcPopulationClient.OwnPace(ped)
        return
    end
    pace(ped, state)
    if not incapacitated(ped, state) then applyBehaviour(ped, state, now) end
end

local function refresh(ped, state, now, isManaged)
    -- A release or a migration may have handed the reactions back to GTA.
    ownReactions(ped, state, false)
    if isManaged then
        if paced[ped] then HumalikeNpcPopulationClient.OwnPace(ped) end
        return
    end
    if drives(state) then
        if paced[ped] then HumalikeNpcPopulationClient.OwnPace(ped) end
    elseif not paced[ped] then
        capPace(ped, state)
    end
    if incapacitated(ped, state) then return end
    -- A flee GTA started before the flag came back is replaced by the plan.
    if hasMind(state) and IsPedFleeing(ped) then
        ClearPedTasks(ped)
        applyBehaviour(ped, state, now)
        return
    end
    local behaviour = behaviourOf(state)
    if behaviour == 'drive' and HumalikeNpcDriving.Refresh(ped, state, now) then return end
    local idle
    if behaviour == 'wander' or behaviour == 'drive' then
        idle = wanderIdle(ped, now)
    else
        idle = scenarioIdle(ped, now)
    end
    if idle then applyBehaviour(ped, state, now) end
end

function HumalikeNpcPopulationClient.Reapply(ped)
    if not DoesEntityExist(ped) or not NetworkHasControlOfEntity(ped) then return false end
    local state = snapshot(ped)
    if state.humalike_npc_kind ~= 'population' or managed(ped, state)
        or incapacitated(ped, state) then
        return false
    end
    local body = bodies[ped]
    if body then body.state = state end
    ClearPedTasks(ped)
    pace(ped, state)
    applyBehaviour(ped, state, GetGameTimer())
    HumalikeNpcPopulationClient.RefreshPace(ped)
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

local function gtaLeftover(ped, populationType, players)
    local cfg = config()
    if not cfg.GtaPopulationTypes[populationType] or IsPedInAnyVehicle(ped, false)
        or IsEntityAMissionEntity(ped) then return false end
    if copsAllowed and cfg.CopPedTypes[GetPedType(ped)] then return false end
    return not nearAnyPlayer(GetEntityCoords(ped), players, cfg.SweepMinPlayerDistance)
end

-- A ped's kind is read from its bag, never from GTA's population type, which
-- differs between how a body was created and which client owns it. Only our
-- own bodies get the full snapshot.
local function bodyState(ped)
    local live = Entity(ped).state
    local kind = live.humalike_npc_kind
    if kind == 'population' then return snapshot(ped), false end
    return nil, kind == nil and live.humalike_npc_id == nil
end

local function forget(ped)
    bodies[ped] = nil
    ownedBodies[ped] = nil
    setPacing(ped, nil)
    stoppedSince[ped], scenarioIdleSince[ped], configured[ped], dressed[ped], paced[ped] =
        nil, nil, nil, nil, nil
end

local function discover(ped, state, netId)
    local body = bodies[ped]
    if body then
        body.state = state
        body.netId = netId or body.netId
        return body
    end
    body = { netId = netId, state = state }
    bodies[ped] = body
    return body
end

function HumalikeNpcPopulationClient.Count()
    local count = 0
    for _ in pairs(bodies) do count = count + 1 end
    return count
end

local function beginPass(now, scan)
    local sweep = scan and enabled
    local list, index = {}, 0
    for ped, body in pairs(bodies) do
        index = index + 1
        list[index] = { ped = ped, body = body }
    end
    table.sort(list, function(a, b) return a.ped < b.ped end)
    return {
        now = now, sweep = sweep, players = sweep and playerPeds() or nil,
        bodies = list, pool = scan and GetGamePool('CPed') or {},
        index = 1, removed = 0, discovered = 0,
        seen = {}, walkers = {}, pacing = {},
    }
end

-- A body this client controls: configured on first sight, refreshed after.
local function visitBody(pass, ped, body)
    if not DoesEntityExist(ped) or IsPedAPlayer(ped)
        or (body.netId and NetworkGetNetworkIdFromEntity(ped) ~= body.netId) then
        forget(ped)
        return
    end
    if not NetworkHasControlOfEntity(ped) then return end
    local state = body.state
    if state.humalike_npc_kind ~= 'population' then
        forget(ped)
        return
    end
    if state.humalike_body_kind == nil then
        -- Not replicated yet when it was read; try the bags again.
        state = snapshot(ped)
        body.state = state
        if state.humalike_npc_kind ~= 'population' then
            forget(ped)
            return
        end
        if state.humalike_body_kind == nil then
            pass.seen[ped] = true -- leave it alone this tick
            return
        end
    end
    pass.seen[ped] = true
    local walks = not drives(state)
    pass.walkers[ped] = walks
    dress(ped, state)
    local isManaged = managed(ped, state)
    pass.pacing[ped] = (walks and not isManaged) or nil
    if configured[ped] == (state.humalike_body_id or true) then
        refresh(ped, state, pass.now, isManaged)
    else
        configure(ped, state, pass.now, isManaged)
    end
end

-- A ped from the pool: a body of ours a bag never announced (whoever owns
-- it: ownership can come later), or a leftover this client may delete.
local function visitPool(pass, ped)
    if bodies[ped] then return end
    if not DoesEntityExist(ped) or IsPedAPlayer(ped) then return end
    local state, unclaimed = bodyState(ped)
    if state then
        pass.discovered = pass.discovered + 1
        local body = discover(ped, state, NetworkGetNetworkIdFromEntity(ped))
        visitBody(pass, ped, body)
    elseif unclaimed and pass.sweep and pass.removed < config().SweepMaxPerTick
        and NetworkHasControlOfEntity(ped)
        and gtaLeftover(ped, GetEntityPopulationType(ped), pass.players) then
        SetEntityAsMissionEntity(ped, true, true)
        DeleteEntity(ped)
        pass.removed = pass.removed + 1
    end
end

local function passLength(pass)
    return #pass.bodies + #pass.pool
end

-- Visits up to `count` entries (bodies first, then the pool); true once done.
local function stepPass(pass, count)
    local last = math.min(passLength(pass), pass.index + count - 1)
    for index = pass.index, last do
        local bodyCount = #pass.bodies
        if index <= bodyCount then
            local item = pass.bodies[index]
            if bodies[item.ped] == item.body then visitBody(pass, item.ped, item.body) end
        else
            visitPool(pass, pass.pool[index - bodyCount])
        end
    end
    pass.index = last + 1
    return pass.index > passLength(pass)
end

local function finishPass(pass)
    local seen = pass.seen
    forgetUnseen(stoppedSince, seen)
    forgetUnseen(scenarioIdleSince, seen)
    forgetUnseen(configured, seen)
    forgetUnseen(dressed, seen)
    forgetUnseen(paced, seen)
    if HumalikeNpcDriving then HumalikeNpcDriving.Forget(seen) end
    ownedBodies = pass.walkers
    paceSet = pass.pacing
    return pass.removed
end

-- A pool pass is due every SweepTickMs, at once after the population is
-- switched on, and whenever a caller forces it.
local function scanDue(now, forced)
    return forced == true or scanRequested or now - lastScanAt >= config().SweepTickMs
end

-- `scan` forces a walk of the ped pool too, finding bodies a bag never
-- announced and (while enabled) sweeping GTA's leftovers; otherwise the pool
-- is walked only when due, and only the known bodies are visited.
function HumalikeNpcPopulationClient.Tick(now, scan)
    scan = scanDue(now, scan)
    if scan then lastScanAt, scanRequested = now, false end
    local pass = beginPass(now, scan)
    stepPass(pass, math.huge)
    return finishPass(pass)
end

-- The same pass as Tick, spread over `slices` frames.
function HumalikeNpcPopulationClient.SlicedTick(now, scan, slices)
    scan = scanDue(now, scan)
    if scan then lastScanAt, scanRequested = now, false end
    local pass = beginPass(now, scan)
    local count = math.max(1, math.ceil(passLength(pass) / math.max(1, slices)))
    currentPass = pass
    while not stepPass(pass, count) do Wait(0) end
    currentPass = nil
    return finishPass(pass)
end

-- SetPedMoveRateOverride lasts one frame, so this runs every frame, but over a
-- list the tick and the takeover hooks keep, with no lookups of its own.
function HumalikeNpcPopulationClient.PaceTick()
    local rate = config().MoveRate
    if rate == 1.0 then return false end
    local any = false
    for ped in pairs(paceSet) do
        SetPedMoveRateOverride(ped, rate)
        any = true
    end
    return any
end

-- Bodies announce themselves: the bag arrives with the entity as it streams
-- in. The entity may not exist locally yet when the handler runs.
local function entityOfBag(bagName)
    local netId = tonumber(bagName:match('^entity:(%d+)$'))
    if not netId then return nil end
    local ped = GetEntityFromStateBagName(bagName)
    if ped and ped > 0 then return ped, netId end
    return nil, netId
end

local function announce(ped, netId)
    if IsPedAPlayer(ped) then return end
    local state = snapshot(ped)
    if state.humalike_npc_kind ~= 'population' then return end
    discover(ped, state, netId)
end

AddStateBagChangeHandler('humalike_npc_kind', nil, function(bagName, _, value)
    if value ~= 'population' then
        local ped = entityOfBag(bagName)
        if ped and bodies[ped] then forget(ped) end
        return
    end
    local ped, netId = entityOfBag(bagName)
    if ped then
        announce(ped, netId)
    elseif netId then
        CreateThread(function()
            local deadline = GetGameTimer() + 1000
            while GetGameTimer() < deadline do
                Wait(50)
                local found = GetEntityFromStateBagName(bagName)
                if found and found > 0 then
                    announce(found, netId)
                    return
                end
            end
        end)
    end
end)

for _, key in ipairs(BODY_KEYS) do
    if key ~= 'humalike_npc_kind' then
        AddStateBagChangeHandler(key, nil, function(bagName, _, value)
            local ped = entityOfBag(bagName)
            local body = ped and bodies[ped] or nil
            if body then rawset(body.state, key, value) end
        end)
    end
end

CreateThread(function()
    while true do
        local density = HumalikeNpcPopulationClient.DensityTick()
        local pacing = HumalikeNpcPopulationClient.PaceTick()
        Wait((density or pacing) and 0 or 250)
    end
end)

-- Frames one pass is spread over, so no frame pays for all of it; a pass that
-- walks the whole ped pool takes twice as many.
local TICK_SLICES = 8
local SCAN_SLICES = 32

CreateThread(function()
    local startedAt = GetGameTimer()
    while true do
        Wait(math.max(0, config().WanderTickMs - (GetGameTimer() - startedAt)))
        local now = GetGameTimer()
        startedAt = now
        local scan = scanDue(now, false)
        HumalikeNpcPopulationClient.SlicedTick(now, scan, scan and SCAN_SLICES or TICK_SLICES)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    stoppedSince, scenarioIdleSince, configured, dressed, paced = {}, {}, {}, {}, {}
    bodies, ownedBodies = {}, {}
    paceSet = {}
    currentPass = nil
    lastScanAt = -math.huge
    if copsDisabled then
        setRandomCops(true)
        copsDisabled = false
    end
end)
