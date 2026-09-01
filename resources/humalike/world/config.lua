WorldConfig = {
    protocolVersion = 1,
    debug = GetConvarInt('humalike_debug', 0) == 1,

    collector = {
        tickMs = GetConvarInt('humalike_world_tick_ms', 20),
        movingIntervalMs = GetConvarInt('humalike_world_moving_interval_ms', 100),
        idleIntervalMs = GetConvarInt('humalike_world_idle_interval_ms', 1000),
        listenerIntervalMs = GetConvarInt('humalike_world_listener_interval_ms', 33),
        movementThreshold = 0.08,
        positionThreshold = 0.15,
        defaultVoiceDistance = 15.0,
        maxVoiceDistance = 50.0,
    },

    npcEdge = {
        enabled = GetConvarInt('humalike_world_npc_edge_enabled', 1) == 1,
        frameIntervalMs = GetConvarInt('humalike_world_npc_edge_interval_ms', 200),
        ticketRetryMs = GetConvarInt('humalike_world_npc_edge_ticket_retry_ms', 3000),
        ticketRefreshMs = GetConvarInt('humalike_world_npc_edge_ticket_refresh_ms', 12000),
        reportRadius = GetConvarInt('humalike_world_npc_report_radius', 150) + 0.0,
        maxNpcsPerFrame = math.min(32,
            math.max(1, GetConvarInt('humalike_world_npc_max_per_frame', 32))),
    },

    voice = {
        enabled = GetConvarInt('humalike_world_voice_enabled', 1) == 1,
        deltaBatchIntervalMs = GetConvarInt('humalike_world_voice_delta_batch_ms', 100),
        snapshotIntervalMs = GetConvarInt('humalike_world_voice_snapshot_ms', 60000),
    },

    cabins = {
        enabled = GetConvarInt('humalike_world_cabin_voice_enabled', 1) == 1,
        retryIntervalMs = math.max(500, GetConvarInt('humalike_world_cabin_retry_ms', 2000)),
        snapshotIntervalMs = math.max(5000,
            GetConvarInt('humalike_world_cabin_snapshot_ms', 30000)),
        startDelayMs = math.max(0, GetConvarInt('humalike_world_cabin_start_delay_ms', 1000)),
    },

    authority = {
        snapshotIntervalMs = GetConvarInt('humalike_world_snapshot_interval_ms', 60000),
    },
}

function HumalikeWorldDebug(format, ...)
    if not WorldConfig.debug then return end
    print(('^5[humalike:world:debug]^7 ' .. format):format(...))
end
