
NpcActions = NpcActions or {}
local TASKS = { 'SCRIPT_TASK_SMART_FLEE_PED', 'SCRIPT_TASK_FOLLOW_NAV_MESH_TO_COORD' }

local function plan()
    return {
        distance = Config.RunAway.Distance,
        durationMs = Config.RunAway.DurationMs,
        arriveRange = Config.RunAway.ArriveRange,
        targetRadius = Config.AmbientControl.ReleaseDistance, -- anywhere the partner may stand
    }
end

local function flee(ped, params)
    SetPedMaxMoveBlendRatio(ped, Config.RunAway.MoveBlend)
    local target = NpcActionLeave.Target(ped, params, Config.AmbientControl.ReleaseDistance)
    if target then
        TaskSmartFleePed(ped, target, Config.RunAway.Distance + 0.0,
            Config.RunAway.DurationMs, false, false)
        return
    end
    TaskFollowNavMeshToCoord(ped, params.x + 0.0, params.y + 0.0, params.z + 0.0,
        Config.RunAway.MoveBlend, -1, 1.0, false, 0.0)
end

NpcActions['run_away'] = function(ped, params)
    NpcActionLeave.Begin(ped, 'run_away', params, plan(), flee)
end

NpcActionSustain['run_away'] = function(ped)
    -- Re-asserted each tick so a new owner keeps the run's pace.
    SetPedMaxMoveBlendRatio(ped, Config.RunAway.MoveBlend)
    NpcActionLeave.Sustain(ped, plan(), flee, TASKS)
end
