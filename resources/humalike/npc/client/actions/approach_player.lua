NpcActions = NpcActions or {}

local TASK = 'SCRIPT_TASK_GO_TO_ENTITY'
local gaits = {}

local function config()
    return Config.Approach
end

local function partnerPed(ped)
    local params = ActionParams[ped]
    if type(params) ~= 'table' or type(params.player_id) ~= 'number' then return nil end
    return ActionTargetPed(ped, params, config().MaxDistance)
end

local function gap(ped, target)
    local origin, coords = GetEntityCoords(ped), GetEntityCoords(target)
    local dx, dy = origin.x - coords.x, origin.y - coords.y
    return math.sqrt(dx * dx + dy * dy)
end

local function arrived(distance)
    return distance <= config().StopRange + config().ArriveSlack
end

local function gaitFor(distance)
    return distance > config().JogDistance and 2.0 or 1.0
end

local function walkTo(ped, target, gait)
    gaits[ped] = gait
    TaskGoToEntity(ped, target, -1, config().StopRange, gait, 1073741824.0, 0)
end

-- The server holds the ped for the partner; once released here the held loop
-- stands it still and keeps it facing them.
local function stop(ped, target)
    gaits[ped] = nil
    ReleaseActionControl(ped)
    ClearPedTasks(ped)
    if target then TaskTurnPedToFaceEntity(ped, target, config().FaceMs) end
end

local function forgetStaleGaits()
    for ped in pairs(gaits) do
        if ActionControlledPeds[ped] ~= 'approach_player' then gaits[ped] = nil end
    end
end

NpcActions['approach_player'] = function(ped, params)
    if BeginStopFollowing then BeginStopFollowing(ped) end
    if NpcActionPedInVehicle(ped) then return end
    local target = ActionTargetPed(ped, params, config().MaxDistance)
    if not target then
        print('[humalike-npc] approach_player: nobody within reach')
        return
    end
    local serverId = params and params.player_id
    if type(serverId) ~= 'number' then
        serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(target))
    end
    ReleaseActionControl(ped)
    ClearPedTasks(ped)
    -- ends_at is server-synced seconds (GetCloudTimeAsInt); GetGameTimer differs per client.
    MarkActionControl(ped, 'approach_player', {
        player_id = serverId,
        ends_at = GetCloudTimeAsInt() + math.ceil(config().TimeoutMs / 1000),
    })
    local distance = gap(ped, target)
    if arrived(distance) then
        stop(ped, target)
        return
    end
    walkTo(ped, target, gaitFor(distance))
end

NpcActionSustain['approach_player'] = function(ped)
    forgetStaleGaits()
    local params = ActionParams[ped]
    if type(params) ~= 'table' or type(params.ends_at) ~= 'number'
        or GetCloudTimeAsInt() >= params.ends_at then
        stop(ped, nil)
        return
    end
    local target = partnerPed(ped)
    if not target then
        stop(ped, nil)
        return
    end
    local distance = gap(ped, target)
    if arrived(distance) then
        stop(ped, target)
        return
    end
    local wanted = gaitFor(distance)
    local dropped = GetScriptTaskStatus(ped, GetHashKey(TASK)) > 1
    if wanted ~= gaits[ped] or dropped then walkTo(ped, target, wanted) end
end
