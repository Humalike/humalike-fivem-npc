
HumalikeDefineConfig(function()
    Config.Wounds = {
        Enabled = HumalikeConvar('humalike_npc_wounds_enabled', 'true') == 'true',
        Display = HumalikeConvar('humalike_npc_wound_display', 'true') == 'true',
        DisplayDistance = tonumber(HumalikeConvar('humalike_npc_wound_display_distance', '3.0')) or 3.0,
        DisplayHeight = tonumber(HumalikeConvar('humalike_npc_wound_display_height', '0.0')) or 0.0,
        DisplayScreenOffset = tonumber(HumalikeConvar('humalike_npc_wound_screen_offset', '0.075')) or 0.075,
        MaxWounds = tonumber(HumalikeConvar('humalike_npc_max_wounds', '6')) or 6,
        MinDamage = tonumber(HumalikeConvar('humalike_npc_wound_min_damage', '5')) or 5,
    }
end)
Config.WoundRegionByBone = {
    [31086] = 'head',       -- SKEL_Head
    [39317] = 'head',       -- SKEL_Neck_1
    [64729] = 'left_arm',   -- SKEL_L_Clavicle
    [45509] = 'left_arm',   -- SKEL_L_UpperArm
    [61163] = 'left_arm',   -- SKEL_L_Forearm
    [18905] = 'left_arm',   -- SKEL_L_Hand
    [10706] = 'right_arm',  -- SKEL_R_Clavicle
    [40269] = 'right_arm',  -- SKEL_R_UpperArm
    [28252] = 'right_arm',  -- SKEL_R_Forearm
    [57005] = 'right_arm',  -- SKEL_R_Hand
    [58271] = 'left_leg',   -- SKEL_L_Thigh
    [63931] = 'left_leg',   -- SKEL_L_Calf
    [14201] = 'left_leg',   -- SKEL_L_Foot
    [51826] = 'right_leg',  -- SKEL_R_Thigh
    [36864] = 'right_leg',  -- SKEL_R_Calf
    [52301] = 'right_leg',  -- SKEL_R_Foot
}
local WOUND_KIND_WEAPONS = {
    stab = {
        'WEAPON_KNIFE', 'WEAPON_DAGGER', 'WEAPON_SWITCHBLADE', 'WEAPON_MACHETE',
        'WEAPON_BOTTLE', 'WEAPON_HATCHET', 'WEAPON_BATTLEAXE', 'WEAPON_STONE_HATCHET',
    },
    blunt = {
        'WEAPON_UNARMED', 'WEAPON_BAT', 'WEAPON_CROWBAR', 'WEAPON_GOLFCLUB',
        'WEAPON_HAMMER', 'WEAPON_KNUCKLE', 'WEAPON_NIGHTSTICK', 'WEAPON_WRENCH',
        'WEAPON_POOLCUE', 'WEAPON_PIPE', 'WEAPON_FLASHLIGHT',
    },
    burn = {
        'WEAPON_MOLOTOV', 'WEAPON_PETROLCAN', 'WEAPON_FLARE', 'WEAPON_FLAREGUN',
        'WEAPON_FIREEXTINGUISHER', 'WEAPON_FIREWORK',
    },
    explosion = {
        'WEAPON_GRENADE', 'WEAPON_STICKYBOMB', 'WEAPON_RPG', 'WEAPON_GRENADELAUNCHER',
        'WEAPON_PIPEBOMB', 'WEAPON_PROXMINE', 'WEAPON_EXPLOSION', 'WEAPON_AIRSTRIKE_ROCKET',
    },
    fall = { 'WEAPON_FALL' },
    vehicle = { 'WEAPON_RUN_OVER_BY_CAR', 'WEAPON_RAMMED_BY_CAR', 'WEAPON_HIT_BY_WATER_CANNON' },
}
Config.WoundKindByWeapon = {}
for kind, names in pairs(WOUND_KIND_WEAPONS) do
    for _, name in ipairs(names) do
        Config.WoundKindByWeapon[GetHashKey(name) % 4294967296] = kind
    end
end
Config.WoundKindFallback = 'gunshot'
Config.WoundSeverityBands = {
    { upTo = 15, severity = 'minor' },
    { upTo = 45, severity = 'serious' },
}
Config.WoundSeverityFallback = 'critical'
Config.WoundSeverityByRegion = {
    head = 'critical',
    torso = 'serious',
    left_arm = 'serious',
    right_arm = 'serious',
    left_leg = 'serious',
    right_leg = 'serious',
}
Config.WoundSofteningKinds = { blunt = true, fall = true, vehicle = true }
Config.WoundSofterSeverity = { critical = 'serious', serious = 'minor', minor = 'minor' }
HumalikeDefineConfig(function()
    Config.WoundLabels = {
        Title = HumalikeConvar('humalike_npc_wound_title', 'Injuries'),
        Deceased = HumalikeConvar('humalike_npc_wound_deceased', 'Deceased'),
        None = HumalikeConvar('humalike_npc_wound_none', 'No visible injuries'),
        Region = {
            head = HumalikeConvar('humalike_npc_wound_region_head', 'Head'),
            torso = HumalikeConvar('humalike_npc_wound_region_torso', 'Torso'),
            left_arm = HumalikeConvar('humalike_npc_wound_region_left_arm', 'Left arm'),
            right_arm = HumalikeConvar('humalike_npc_wound_region_right_arm', 'Right arm'),
            left_leg = HumalikeConvar('humalike_npc_wound_region_left_leg', 'Left leg'),
            right_leg = HumalikeConvar('humalike_npc_wound_region_right_leg', 'Right leg'),
        },
        Kind = {
            gunshot = HumalikeConvar('humalike_npc_wound_kind_gunshot', 'Gunshot wound'),
            stab = HumalikeConvar('humalike_npc_wound_kind_stab', 'Stab wound'),
            blunt = HumalikeConvar('humalike_npc_wound_kind_blunt', 'Blunt trauma'),
            burn = HumalikeConvar('humalike_npc_wound_kind_burn', 'Burn'),
            explosion = HumalikeConvar('humalike_npc_wound_kind_explosion', 'Blast injury'),
            fall = HumalikeConvar('humalike_npc_wound_kind_fall', 'Fall injury'),
            vehicle = HumalikeConvar('humalike_npc_wound_kind_vehicle', 'Vehicle impact'),
        },
        Severity = {
            minor = HumalikeConvar('humalike_npc_wound_severity_minor', 'minor'),
            serious = HumalikeConvar('humalike_npc_wound_severity_serious', 'serious'),
            critical = HumalikeConvar('humalike_npc_wound_severity_critical', 'critical'),
        },
    }
end)
function HumalikeClassifyWound(boneId, weaponHash, damage)
    local region = Config.WoundRegionByBone[tonumber(boneId) or -1] or 'torso'
    local kind = Config.WoundKindByWeapon[(tonumber(weaponHash) or 0) % 4294967296]
        or Config.WoundKindFallback
    local amount = tonumber(damage) or 0
    local severity
    if amount > 0 then
        severity = Config.WoundSeverityFallback
        for _, band in ipairs(Config.WoundSeverityBands) do
            if amount <= band.upTo then
                severity = band.severity
                break
            end
        end
    else
        severity = Config.WoundSeverityByRegion[region] or 'serious'
        if Config.WoundSofteningKinds[kind] then
            severity = Config.WoundSofterSeverity[severity] or severity
        end
    end
    return { region = region, kind = kind, severity = severity }
end
