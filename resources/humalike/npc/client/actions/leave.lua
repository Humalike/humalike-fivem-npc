NpcActionLeave = NpcActionLeave or {}
local PAVEMENT_FLAGS = 2 | 4 | 8

function NpcActionLeave.Target(ped, params, radius)
    return ActionTargetPed(ped, params, radius)
end

local function snap(x, y, z)
    if not GetSafeCoordForPed then return x, y, z end
    local found, safe = GetSafeCoordForPed(x, y, z, false, PAVEMENT_FLAGS)
    if found and safe then return safe.x, safe.y, safe.z end
    return x, y, z
end

function NpcActionLeave.AwayPoint(ped, params, distance, targetRadius)
    local origin = GetEntityCoords(ped)
    local target = NpcActionLeave.Target(ped, params, targetRadius)
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
    return snap(origin.x + dx / length * distance, origin.y + dy / length * distance, origin.z)
end

-- ends_at is server-synced seconds (GetCloudTimeAsInt); GetGameTimer differs per client.
function NpcActionLeave.Begin(ped, key, params, plan, issue)
    if NpcActionPedInVehicle(ped) and BeginStopFollowing then
        BeginStopFollowing(ped)
        return false
    end
    local x, y, z = NpcActionLeave.AwayPoint(ped, params, plan.distance, plan.targetRadius)
    local held = {
        x = x,
        y = y,
        z = z,
        player_id = params and params.player_id or nil,
        ends_at = GetCloudTimeAsInt() + math.ceil(plan.durationMs / 1000),
    }
    ReleaseActionControl(ped)
    ClearPedTasks(ped)
    MarkActionControl(ped, key, held)
    issue(ped, held)
    return true
end

function NpcActionLeave.Stop(ped)
    ReleaseActionControl(ped)
    ClearPedTasks(ped)
    TaskWanderStandard(ped, 10.0, 10)
end

local function taskRunning(ped, tasks)
    for _, task in ipairs(tasks) do
        if GetScriptTaskStatus(ped, GetHashKey(task)) <= 1 then return true end
    end
    return false
end

function NpcActionLeave.Sustain(ped, plan, issue, tasks)
    local params = ActionParams[ped]
    if type(params) ~= 'table' or type(params.x) ~= 'number' or type(params.y) ~= 'number'
        or type(params.z) ~= 'number' or type(params.ends_at) ~= 'number' then
        NpcActionLeave.Stop(ped)
        return
    end
    local coords = GetEntityCoords(ped)
    local dx, dy = coords.x - params.x, coords.y - params.y
    local arrived = math.sqrt(dx * dx + dy * dy) <= plan.arriveRange
    if arrived or GetCloudTimeAsInt() >= params.ends_at then
        NpcActionLeave.Stop(ped)
        return
    end
    if not taskRunning(ped, tasks) then issue(ped, params) end
end
