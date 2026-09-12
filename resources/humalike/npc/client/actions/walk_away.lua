
NpcActions = NpcActions or {}
local TASKS = { 'SCRIPT_TASK_FOLLOW_NAV_MESH_TO_COORD' }

local function plan()
    return {
        distance = Config.WalkAway.Distance,
        durationMs = Config.WalkAway.TimeoutMs,
        arriveRange = Config.WalkAway.ArriveRange,
        targetRadius = Config.WalkAway.TargetRadius,
    }
end

local function walkTo(ped, params)
    TaskFollowNavMeshToCoord(ped, params.x + 0.0, params.y + 0.0, params.z + 0.0,
        1.0, -1, 1.0, false, 0.0)
end

NpcActions['walk_away'] = function(ped, params)
    NpcActionLeave.Begin(ped, 'walk_away', params, plan(), walkTo)
end

NpcActionSustain['walk_away'] = function(ped)
    NpcActionLeave.Sustain(ped, plan(), walkTo, TASKS)
end
