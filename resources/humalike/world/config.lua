HumalikeDefineConfig(function()
    WorldConfig = {
        protocolVersion = 1,
        debug = HumalikeConvarInt('humalike_debug', 0) == 1,

        collector = {
            tickMs = HumalikeConvarInt('humalike_world_tick_ms', 20),
            movingIntervalMs = HumalikeConvarInt('humalike_world_moving_interval_ms', 200),
            idleIntervalMs = HumalikeConvarInt('humalike_world_idle_interval_ms', 1000),
            listenerIntervalMs = HumalikeConvarInt('humalike_world_listener_interval_ms', 50),
            movementThreshold = 0.08,
            positionThreshold = 0.15,
            defaultVoiceDistance = 15.0,
            maxVoiceDistance = 50.0,
        },

        npcEdge = {
            enabled = HumalikeConvarInt('humalike_world_npc_edge_enabled', 1) == 1,
            -- Never below the edge's own tick: it keeps one frame per 200 ms and a
            -- newer one replaces it whole, so deltas sent faster would be dropped.
            frameIntervalMs = math.max(200, HumalikeConvarInt('humalike_world_npc_edge_interval_ms', 200)),
            ticketRetryMs = HumalikeConvarInt('humalike_world_npc_edge_ticket_retry_ms', 3000),
            ticketRefreshMs = HumalikeConvarInt('humalike_world_npc_edge_ticket_refresh_ms', 12000),
            reportRadius = HumalikeConvarInt('humalike_world_npc_report_radius', 150) + 0.0,
            maxNpcsPerFrame = math.min(32,
                math.max(1, HumalikeConvarInt('humalike_world_npc_max_per_frame', 32))),
        },

        voice = {
            enabled = HumalikeConvarInt('humalike_world_voice_enabled', 1) == 1,
            deltaBatchIntervalMs = HumalikeConvarInt('humalike_world_voice_delta_batch_ms', 100),
            snapshotIntervalMs = HumalikeConvarInt('humalike_world_voice_snapshot_ms', 60000),
        },

        cabins = {
            enabled = HumalikeConvarInt('humalike_world_cabin_voice_enabled', 1) == 1,
            retryIntervalMs = math.max(500, HumalikeConvarInt('humalike_world_cabin_retry_ms', 2000)),
            snapshotIntervalMs = math.max(5000,
                HumalikeConvarInt('humalike_world_cabin_snapshot_ms', 30000)),
            startDelayMs = math.max(0, HumalikeConvarInt('humalike_world_cabin_start_delay_ms', 1000)),
        },

        authority = {
            snapshotIntervalMs = HumalikeConvarInt('humalike_world_snapshot_interval_ms', 60000),
        },
    }
end)

function HumalikeWorldDebug(format, ...)
    if not WorldConfig.debug then return end
    print(('^5[humalike:world:debug]^7 ' .. format):format(...))
end
