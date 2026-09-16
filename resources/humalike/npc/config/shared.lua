Config = {}
Config.Debug = GetConvar('humalike_debug', 'false') == 'true'
    or GetConvar('humalike_debug', '0') == '1'
function HumalikeDebug(fmt, ...)
    if not Config.Debug then return end
    print(('^3[humalike:npc:debug]^7 ' .. fmt):format(...))
end
Config.Integrations = {
    player = GetConvar('humalike_player', 'auto'),
    inventory = GetConvar('humalike_inventory', 'auto'),
    dispatch = GetConvar('humalike_dispatch', 'auto'),
    actions = GetConvar('humalike_actions', 'auto'),
    interaction = GetConvar('humalike_interaction', 'auto'),
}

Config.PlayerSessionSyncIntervalMs = 15000
Config.AppearancePollIntervalMs = 1000
Config.AppearanceUpsertDebounceMs = 750
Config.AppearancePropIds = { 0, 1, 2, 6, 7 }
Config.AppearanceMaxDrawableId = 65535
Config.AmbientLeaseScopeDistance = 200.0
Config.AmbientLeaseScopeTickMs = 2000
Config.AmbientControl = {
    InteractionDistance = 3.0,
    ServerValidationDistance = 4.5,
    ReleaseDistance = 30.0,
    RequestCooldownMs = 750,
    StandTaskDurationMs = 2000,
    StandTaskRefreshMs = 500,
    FaceToleranceDeg = 25.0,
}
Config.Population = {
    SpawnPointTimeoutMs = 2000,
    SpawnPointTolerance = 60.0,
    SpawnPointClientRange = 250.0, -- metres a client may be from the first candidate to be asked
    SpawnTimeoutMs = 30000,
    MinPlayerDistance = 40.0,
    ReconcileTickMs = 2000,
    LeaseGraceMs = 30000,
    HeartbeatMs = 30000,
    EdgeLostHeartbeats = 3, -- silent heartbeats before the street goes back to GTA
    RetryBackoffMs = 500,
    RetryBackoffCapMs = 30000,
    ReleaseMaxAttempts = 8,
    WanderTickMs = 1000,
    MoveRate = 0.82, -- fraction of the walk animation rate; 1.0 is the CreatePed default
    WanderIdleMs = 5000,
    ScenarioIdleMs = 10000,
    SweepTickMs = 2000,
    SweepMinPlayerDistance = 15.0,
    SweepMaxPerTick = 5,
    DriverSpawnOffset = 2.5, -- metres beside the car a driver is created before being seated
    VehicleNodeClearance = 5.0, -- metres: a road node holding a vehicle is not a spawn point
    FeatureReportTimeoutMs = 20000, -- a capability post with no callback by then is treated as lost
    VehiclePointReuseMs = 5000, -- two drivers resolving at once must not share a node; the client checks real vehicles
    GtaPopulationTypes = { [4] = true, [5] = true },
    CopPedTypes = { [6] = true, [27] = true }, -- GetPedType cop, swat
}
Config.Vehicles = {
    WarpDistance = 6.0, -- metres: an unseated driver this close to its free car is put straight in
    DriveSpeed = 12.0, -- m/s for cruising
    DriveStyle = 786603, -- driving style flags: normal, obey traffic
    EnterTimeoutMs = 15000, -- the enter-vehicle task timeout; also the gap between attempts
    BrakeAction = 27, -- TaskVehicleTempAction: brake
    ReturnDistance = 60.0, -- metres: how far a driver on foot walks back to its own car when told to
    ReturnTimeoutMs = 45000, -- the whole walk-back-and-board attempt, before the body is given back
}
Config.Shove = {
    TickMs = 100,
    MinSpeed = 0.5,
    KnockdownWindowMs = 600,
    ReportGapMs = 3000,
    ServerGapMs = 2000, -- must stay below ReportGapMs
    ForgetAfterMs = 10000,
    MeleeIgnoreMs = 1000,
    MaxDistance = 6.0,
    MaxReportsPerWindow = 4,
    ReportWindowMs = 2000,
}
Config.Combat = {
    MeleeReportDistance = 6.0,
    MaxReportDistance = 150.0,
    MeleeWeapons = {
        WEAPON_UNARMED = true, WEAPON_KNIFE = true, WEAPON_NIGHTSTICK = true,
        WEAPON_HAMMER = true, WEAPON_BAT = true, WEAPON_GOLFCLUB = true,
        WEAPON_CROWBAR = true, WEAPON_BOTTLE = true, WEAPON_DAGGER = true,
        WEAPON_HATCHET = true, WEAPON_KNUCKLE = true, WEAPON_MACHETE = true,
        WEAPON_FLASHLIGHT = true, WEAPON_SWITCHBLADE = true, WEAPON_POOLCUE = true,
        WEAPON_WRENCH = true, WEAPON_BATTLEAXE = true, WEAPON_STONE_HATCHET = true,
    },
}
function HumalikeUnsignedHash(value)
    return value < 0 and value + 4294967296 or value
end
function HumalikeValidId(value)
    return type(value) == 'string' and value ~= '' and #value <= 64
end
-- Seats -1..7 cover every stock vehicle; both natives exist on client and server.
function HumalikePlayerInVehicle(vehicle)
    for seat = -1, 7 do
        local occupant = GetPedInVehicleSeat(vehicle, seat)
        if occupant and occupant > 0 and IsPedAPlayer(occupant) then return true end
    end
    return false
end
function HumalikeValidCoordinate(value)
    return type(value) == 'number' and value == value and math.abs(value) <= 10000
end
function HumalikeDistanceSquared(left, right)
    local dx, dy, dz = left.x - right.x, left.y - right.y, left.z - right.z
    return dx * dx + dy * dy + dz * dz
end
function HumalikeJobList(value)
    local names = {}
    for name in tostring(value or ''):gmatch('[^,]+') do
        local trimmed = name:match('^%s*(.-)%s*$')
        if trimmed ~= '' then names[#names + 1] = trimmed end
    end
    return names
end
Config.Wounded = {
    Enabled = GetConvar('humalike_npc_wounded_enabled', 'true') == 'true',
    DurationMs = tonumber(GetConvar('humalike_npc_wounded_duration', '300000')) or 300000,
    DeathChancePercent = tonumber(GetConvar('humalike_npc_death_chance', '5')) or 5,
    LingerAfterReviveMs = tonumber(GetConvar('humalike_npc_revive_linger', '30000')) or 30000,
    LingerRadius = tonumber(GetConvar('humalike_npc_revive_linger_radius', '20')) or 20.0,
    MedicJobs = HumalikeJobList(GetConvar('humalike_npc_medic_jobs', 'ambulance,ems')),
    PoliceJobs = HumalikeJobList(GetConvar('humalike_npc_police_jobs', 'police')),
    RequireDuty = GetConvar('humalike_npc_wounded_require_duty', 'true') == 'true',
    ReviveLabel = GetConvar('humalike_npc_revive_label', 'Revive'),
    ReviveProgressLabel = GetConvar('humalike_npc_revive_progress', 'Treating patient'),
    MortuaryLabel = GetConvar('humalike_npc_mortuary_label', 'Send to mortuary'),
    MortuaryProgressLabel = GetConvar('humalike_npc_mortuary_progress', 'Securing the body'),
    ReviveDurationMs = tonumber(GetConvar('humalike_npc_revive_duration', '10000')) or 10000,
    MortuaryDurationMs = tonumber(GetConvar('humalike_npc_mortuary_duration', '5000')) or 5000,
    TreatmentDistance = tonumber(GetConvar('humalike_npc_treatment_distance', '6.0')) or 6.0,
    RolesRefreshMs = 5000,
    DeceasedRetentionMs = tonumber(GetConvar('humalike_npc_deceased_retention', '900000')) or 900000,
    Dispatch = {
        Enabled = GetConvar('humalike_npc_medical_dispatch', 'true') == 'true',
        Chance = tonumber(GetConvar('humalike_npc_medical_dispatch_chance', '100')) or 100,
        DelayMs = tonumber(GetConvar('humalike_npc_medical_dispatch_delay', '10000')) or 10000,
        ThrottleSeconds = tonumber(GetConvar('humalike_npc_medical_dispatch_throttle', '30')) or 30,
        NotifyMortuary = GetConvar('humalike_npc_mortuary_dispatch', 'true') == 'true',
    },
}

Config.AmbientRevive = {
    InteractionDistance = 3.0,
    DurationMs = 5000,
    CompletionToleranceMs = 500,
    SessionTimeoutMs = 10000,
}
Config.NpcLabels = {
    Enabled = GetConvar('humalike_npc_labels_enabled', 'true') == 'true',
    MaxDistance = tonumber(GetConvar('humalike_npc_labels_distance', '14.0')) or 14.0,
    Height = tonumber(GetConvar('humalike_npc_labels_height', '0.98')) or 0.98,
    Scale = tonumber(GetConvar('humalike_npc_labels_scale', '1.0')) or 1.0,
    CandidateRefreshMs = 200,
    CandidateMargin = 3.0,
    RenderFps = 60,
    DefaultLanguage = GetConvar('humalike_npc_labels_default_language', 'pl'),
    ShowDefaultLanguage = GetConvar('humalike_npc_labels_show_default_language', 'false') == 'true',
    LanguageLabels = { pl = 'pl', en = 'en', de = 'de', es = 'es', fr = 'fr' },
}
Config.RosterSyncIntervalMs = 30000
Config.SupportedActions = {
    'wave',
    'start_dancing',
    'interrupt_animation',
    'kneel',
    'hands_up',
    'punch',
    'stand_up',
    'follow_player',
    'stop_following',
    'hold_position',
    'release_movement',
    'enter_vehicle',
    'enter_own_vehicle',
    'exit_vehicle',
    'walk_away',
    'run_away',
}
Config.ActionSustainTickMs = 250
Config.PoseAbandonMs = tonumber(GetConvar('humalike_npc_pose_abandon_ms', '120000')) or 120000
Config.PoseAbandonRadius = tonumber(GetConvar('humalike_npc_pose_abandon_radius', '60')) or 60.0
Config.PoseAbandonTickMs = 5000
Config.PoseThreat = {
    Enabled = GetConvar('humalike_npc_pose_threat_watch', 'true') == 'true',
    Radius = tonumber(GetConvar('humalike_npc_pose_threat_radius', '30')) or 30.0,
    ClearMs = tonumber(GetConvar('humalike_npc_pose_threat_clear_ms', '10000')) or 10000,
}
Config.PoseThreatTickMs = 2500
Config.Follow = {
    MaxDistance = 6.0,
    OffsetBehind = -1.5,
    StoppingRange = 2.0,
    RunBehindDistance = 8.0,
    SprintBehindDistance = 15.0,
    RunSpeedThreshold = 3.0,
    SprintSpeedThreshold = 6.2,
    VehicleTaskTimeoutMs = 10000,
    VehicleRetryMs = 1500,
    VehicleEntrySpeed = 2.0,
}
Config.VehicleDamage = {
    PollIntervalMs = 250,
    ServerPollIntervalMs = 250,
    ObservationRetentionMs = 60000,
    PendingCandidateMs = 30000,
    UntrustedEventThrottleMs = 100,
    SignificantHealthDrop = 50.0,
    SevereHealthDrop = 200.0,
    SevereEngineHealth = 300.0,
    CooldownMs = 10000,
    ServerCooldownMs = 10000,
}
Config.WalkAway = {
    Distance = 30.0,
    ArriveRange = 3.0,
    TimeoutMs = 60000,
    TargetRadius = 25.0,
}
Config.RunAway = {
    Distance = 60.0,
    DurationMs = 12000, -- most runs end here and settle into a wander
    ArriveRange = 5.0,
    MoveBlend = 2.1, -- 1 walk, 2 run, 3 sprint
}
Config.Wave = {
    DurationMs = 3000,
}
Config.Punch = {
    MaxDistance = 4.0,
    DurationMs = 4000,
}
Config.GiveItem = {
    MaxDistance = 5.0,
    MaxQuantity = 100,
    AllowlistEnabled = false,
    AllowedItems = {
        water = true,
    },
}
Config.Robbery = {
    MaxDistance = 5.0,
    HandoverAnimMs = 1500,
}
