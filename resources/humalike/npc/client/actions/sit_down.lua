NpcActions = NpcActions or {}

-- A bench seat when one is within reach, the ground where the ped stands otherwise.
local GROUND_SCENARIO = 'WORLD_HUMAN_PICNIC'
local BENCH_MODELS = {
    'prop_bench_01a', 'prop_bench_01b', 'prop_bench_01c', 'prop_bench_02', 'prop_bench_03',
    'prop_bench_04', 'prop_bench_05', 'prop_bench_06', 'prop_bench_07', 'prop_bench_08',
    'prop_bench_09', 'prop_bench_10', 'prop_bench_11', 'prop_wait_bench_01',
}
local settleUntil = {}

local function config()
    return Config.SitDown
end

local function nearestBench(ped)
    local origin = GetEntityCoords(ped)
    local best, bestDistance = nil, config().BenchRadius
    for _, model in ipairs(BENCH_MODELS) do
        local object = GetClosestObjectOfType(origin.x, origin.y, origin.z, bestDistance,
            GetHashKey(model), false, false, false)
        if object ~= 0 and DoesEntityExist(object) then
            local coords = GetEntityCoords(object)
            local dx, dy = coords.x - origin.x, coords.y - origin.y
            local distance = math.sqrt(dx * dx + dy * dy)
            if distance < bestDistance then
                best, bestDistance = { x = coords.x, y = coords.y, z = coords.z }, distance
            end
        end
    end
    return best
end

local function issue(ped, params)
    if params.mode == 'bench' then
        TaskUseNearestScenarioToCoord(ped, params.x + 0.0, params.y + 0.0, params.z + 0.0,
            config().BenchScenarioRange, -1)
        settleUntil[ped] = GetGameTimer() + config().BenchSettleMs
        return
    end
    TaskStartScenarioInPlace(ped, GROUND_SCENARIO, 0, true)
    settleUntil[ped] = GetGameTimer() + config().GroundSettleMs
end

local function stand(ped)
    settleUntil[ped] = nil
    ReleaseActionControl(ped)
    ClearPedTasks(ped)
end

local function forgetStale()
    for ped in pairs(settleUntil) do
        if ActionControlledPeds[ped] ~= 'sit_down' then settleUntil[ped] = nil end
    end
end

NpcActions['sit_down'] = function(ped, _params)
    if NpcActionPedInVehicle(ped) then return end
    if BeginStopFollowing then
        BeginStopFollowing(ped)
    else
        ReleaseActionControl(ped)
        ClearPedTasks(ped)
    end
    local bench = nearestBench(ped)
    local params = bench and { mode = 'bench', x = bench.x, y = bench.y, z = bench.z }
        or { mode = 'ground' }
    MarkActionControl(ped, 'sit_down', params)
    issue(ped, params)
end

NpcActionSustain['sit_down'] = function(ped)
    forgetStale()
    if NpcActionPedInVehicle(ped) then return end
    local params = ActionParams[ped]
    if type(params) ~= 'table' or (params.mode ~= 'bench' and params.mode ~= 'ground') then
        stand(ped)
        return
    end
    if IsPedUsingAnyScenario(ped) then
        settleUntil[ped] = nil
        return
    end
    -- No timer means a new owner or a seat that ended: sit again.
    if not settleUntil[ped] then
        issue(ped, params)
        return
    end
    if GetGameTimer() < settleUntil[ped] then return end
    -- The seat never took: a bench that could not be reached falls back to the
    -- ground; a ground sit that never played gives up rather than retry forever.
    if params.mode == 'bench' then
        params = { mode = 'ground' }
        MarkActionControl(ped, 'sit_down', params)
        ClearPedTasks(ped)
        issue(ped, params)
        return
    end
    stand(ped)
end
