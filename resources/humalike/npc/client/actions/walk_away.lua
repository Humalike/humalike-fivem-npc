
NpcActions = NpcActions or {}
local walkDeadline = {}

local function forgetStaleDeadlines()
    for ped in pairs(walkDeadline) do
        if ActionControlledPeds[ped] ~= 'walk_away' then walkDeadline[ped] = nil end
    end
end

local function destinationFrom(ped, params)
    local origin = GetEntityCoords(ped)
    local target = ActionTargetPed(ped, params, 25.0)
    local dx, dy = 0.0, 0.0
    if target then
        local from = GetEntityCoords(target)
        dx, dy = origin.x - from.x, origin.y - from.y
    end
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 0.5 then
        local heading = math.rad(GetEntityHeading(ped))
        dx, dy, length = -math.sin(heading), math.cos(heading), 1.0
    end
    local distance = Config.WalkAway.Distance
    return origin.x + dx / length * distance, origin.y + dy / length * distance, origin.z
end

local function walkTo(ped, params)
    TaskFollowNavMeshToCoord(ped, params.x + 0.0, params.y + 0.0, params.z + 0.0,
        1.0, -1, 1.0, false, 0.0)
end

NpcActions['walk_away'] = function(ped, params)
    local x, y, z = destinationFrom(ped, params)
    ReleaseActionControl(ped)
    ClearPedTasks(ped)
    MarkActionControl(ped, 'walk_away', { x = x, y = y, z = z })
    walkDeadline[ped] = GetGameTimer() + (Config.WalkAway.TimeoutMs or 60000)
    walkTo(ped, { x = x, y = y, z = z })
end

NpcActionSustain['walk_away'] = function(ped)
    forgetStaleDeadlines()
    local params = ActionParams[ped]
    if type(params) ~= 'table' or type(params.x) ~= 'number'
        or type(params.y) ~= 'number' or type(params.z) ~= 'number' then
        walkDeadline[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    walkDeadline[ped] = walkDeadline[ped]
        or GetGameTimer() + (Config.WalkAway.TimeoutMs or 60000)
    local coords = GetEntityCoords(ped)
    local dx, dy = coords.x - params.x, coords.y - params.y
    local arrived = math.sqrt(dx * dx + dy * dy) <= Config.WalkAway.ArriveRange
    if arrived or GetGameTimer() >= walkDeadline[ped] then
        walkDeadline[ped] = nil
        ReleaseActionControl(ped)
        ClearPedTasks(ped)
        TaskWanderStandard(ped, 10.0, 10)
        return
    end
    local dropped = GetScriptTaskStatus(
        ped, GetHashKey('SCRIPT_TASK_FOLLOW_NAV_MESH_TO_COORD')) > 1
    if dropped then walkTo(ped, params) end
end
