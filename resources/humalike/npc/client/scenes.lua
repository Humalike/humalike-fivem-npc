HumalikeNpcScenesClient = HumalikeNpcScenesClient or {}

-- Inferred, not verified in-game: a min move blend ratio of 2.0 makes a
-- wandering ped run instead of walk.
local CORNER_SCENARIOS = {
    'WORLD_HUMAN_HANG_OUT_STREET', 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_STAND_MOBILE',
    'WORLD_HUMAN_DRINKING', 'WORLD_HUMAN_STAND_IMPATIENT',
}
local SIDEWALK_SCENARIOS = {
    'WORLD_HUMAN_LEANING', 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_SMOKING',
    'WORLD_HUMAN_STAND_IMPATIENT',
}
local SCENARIO_ARCHETYPES = { corner = CORNER_SCENARIOS, sidewalk = SIDEWALK_SCENARIOS }
local AMBLING = { corner = true, sidewalk = true, walk = true } -- run and riders keep their pace
local VEHICLE_ARCHETYPES = { car = true, bikes = true, ride = true }
local FOLLOW_TASK = 'SCRIPT_TASK_FOLLOW_TO_OFFSET_OF_ENTITY'
local ENTER_TASK = 'SCRIPT_TASK_ENTER_VEHICLE'
local DRIVE_WANDER_TASK = 'SCRIPT_TASK_VEHICLE_DRIVE_WANDER'

local turnUntil = {}
local turned = {}
local heldInit = {}
local stoppedSince = {}
local roles = {}
local following = {}
local enteredAt = {}
local vehicleLost = {}

local function cfg()
    return Config.Scenes
end

local function population()
    return HumalikeNpcPopulationClient
end

local function entityOf(networkId)
    if type(networkId) ~= 'number' or networkId <= 0
        or not NetworkDoesEntityExistWithNetworkId(networkId) then return nil end
    local entity = NetworkGetEntityFromNetworkId(networkId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end
    return entity
end

-- A dead leader leads nobody: followers fall back as if it were not local.
local function leaderOf(scene)
    local leader = entityOf(scene.leader_net)
    if not leader or IsEntityDead(leader) then return nil end
    return leader
end

local function taskDropped(ped, taskName)
    return GetScriptTaskStatus(ped, GetHashKey(taskName)) > 1
end

function HumalikeNpcScenesClient.Ambles(scene)
    return AMBLING[scene.archetype] == true
end

-- Riders are meant to be in vehicles, so only death and ragdoll count.
function HumalikeNpcScenesClient.Incapacitated(ped)
    return IsEntityDead(ped) or IsPedRagdoll(ped)
end

local function idle(ped, now, threshold)
    return population().Idle(ped, now, threshold)
end

local function scenarioFor(scene)
    local list = SCENARIO_ARCHETYPES[scene.archetype]
    return list[(math.max(tonumber(scene.slot) or 0, 0) % #list) + 1]
end

local function follow(ped, scene, speed)
    local leader = leaderOf(scene)
    if not leader then
        following[ped] = false
        TaskWanderStandard(ped, 10.0, 10)
        return
    end
    following[ped] = true
    TaskFollowToOffsetOfEntity(ped, leader, tonumber(scene.ox) or 0.0, tonumber(scene.oy) or 0.0,
        0.0, speed, -1, cfg().FollowStopRange, true)
end

local function leaderVehicle(scene)
    local leader = leaderOf(scene)
    if not leader or not IsPedInAnyVehicle(leader, false) then return nil end
    local vehicle = GetVehiclePedIsIn(leader, false)
    if vehicle == 0 then return nil end
    return vehicle
end

local function bikeFollower(scene)
    return scene.archetype == 'bikes' and scene.slot ~= 0
end

-- A seat someone else took, or a player anywhere in the vehicle, ends the
-- ride for this body: it walks off once and is not sent back.
local function seatTaken(ped, vehicle, seat)
    local occupant = GetPedInVehicleSeat(vehicle, seat)
    return (occupant ~= 0 and occupant ~= ped) or HumalikePlayerInVehicle(vehicle)
end

local function enter(ped, scene, vehicle, now)
    local seat = tonumber(scene.seat) or -1
    if seatTaken(ped, vehicle, seat) then
        vehicleLost[ped] = true
        TaskWanderStandard(ped, 10.0, 10)
        return
    end
    local timeout = cfg().EnterTimeoutMs
    if enteredAt[ped] and now - enteredAt[ped] < timeout then return end
    enteredAt[ped] = now
    TaskEnterVehicle(ped, vehicle, timeout, seat, 1.0, 1, 0)
end

local function drive(ped, scene, vehicle)
    local tunables = cfg()
    SetVehicleEngineOn(vehicle, true, true, false)
    stoppedSince[ped] = nil
    if bikeFollower(scene) then
        local lead = leaderVehicle(scene)
        if lead then
            following[ped] = true
            TaskVehicleFollow(ped, vehicle, lead, tunables.DriveStyle, tunables.DriveSpeed,
                tunables.FollowDistance)
            return
        end
    end
    following[ped] = false
    TaskVehicleDriveWander(ped, vehicle, tunables.DriveSpeed, tunables.DriveStyle)
end

local function applyVehicle(ped, scene, now)
    local vehicle = entityOf(scene.vehicle_net)
    if not vehicle then
        -- The vehicle is gone (stolen, despawned): the body walks until the edge culls it.
        if not IsPedInAnyVehicle(ped, false) then TaskWanderStandard(ped, 10.0, 10) end
        return
    end
    if not IsPedInVehicle(ped, vehicle, false) then
        if not vehicleLost[ped] then enter(ped, scene, vehicle, now) end
        return
    end
    if scene.seat ~= -1 then return end
    drive(ped, scene, vehicle)
end

-- The slot and the leader decide what a body does; a re-slotted crew changes both.
local function roleOf(scene)
    return tostring(scene.slot) .. ':' .. tostring(scene.leader_net)
end

local function apply(ped, scene, now)
    population().MarkTasked(ped, now)
    roles[ped] = roleOf(scene)
    local archetype = scene.archetype
    local tunables = cfg()
    if SCENARIO_ARCHETYPES[archetype] then
        if not turned[ped] then
            turned[ped] = true
            turnUntil[ped] = now + tunables.TurnMs
            TaskTurnPedToFaceCoord(ped, scene.ax, scene.ay, scene.az, tunables.TurnMs)
            return
        end
        turnUntil[ped] = nil
        TaskStartScenarioInPlace(ped, scenarioFor(scene), 0, true)
    elseif archetype == 'walk' or archetype == 'run' then
        local running = archetype == 'run'
        if scene.slot ~= 0 then
            follow(ped, scene, running and tunables.RunSpeed or tunables.WalkSpeed)
            return
        end
        if running then
            SetPedMinMoveBlendRatio(ped, tunables.RunMinBlend)
            SetPedMaxMoveBlendRatio(ped, tunables.RunMaxBlend)
        end
        TaskWanderStandard(ped, 10.0, 10)
    elseif VEHICLE_ARCHETYPES[archetype] then
        applyVehicle(ped, scene, now)
    else
        TaskWanderStandard(ped, 10.0, 10)
    end
end

-- Brakes a seated scene driver; true when it did, so a hold on the driver
-- itself (ambient control) leaves the stand-still to us.
function HumalikeNpcScenesClient.Brake(ped, scene)
    scene = scene or (DoesEntityExist(ped) and Entity(ped).state.humalike_scene or nil)
    if type(scene) ~= 'table' or scene.seat ~= -1 or not IsPedInAnyVehicle(ped, false) then
        return false
    end
    local vehicle = entityOf(scene.vehicle_net)
    if not vehicle or GetPedInVehicleSeat(vehicle, -1) ~= ped then return false end
    TaskVehicleTempAction(ped, vehicle, cfg().BrakeAction, Config.AmbientControl.StandTaskDurationMs)
    return true
end

-- A held crew stands where it is; a driver brakes and passengers sit.
local function applyHeld(ped, scene)
    if not heldInit[ped] then
        ClearPedTasks(ped)
        heldInit[ped] = true
    end
    if IsPedInAnyVehicle(ped, false) then
        HumalikeNpcScenesClient.Brake(ped, scene)
        return
    end
    TaskStandStill(ped, Config.AmbientControl.StandTaskDurationMs)
end

-- A follower keeps its follow task until it drops; wandering without a
-- leader, it takes the leader up as soon as one is there.
local function refreshFollower(ped, scene, now)
    local leader = leaderOf(scene)
    if following[ped] then
        if not leader or taskDropped(ped, FOLLOW_TASK) then apply(ped, scene, now) end
        return
    end
    if leader or idle(ped, now, Config.Population.WanderIdleMs) then apply(ped, scene, now) end
end

local function refreshDriver(ped, scene, vehicle, now)
    if GetEntitySpeed(vehicle) >= cfg().VehicleStoppedSpeed then
        stoppedSince[ped] = nil
    else
        stoppedSince[ped] = stoppedSince[ped] or now
    end
    if bikeFollower(scene) then
        local lead = leaderVehicle(scene)
        if following[ped] ~= (lead ~= nil) then
            apply(ped, scene, now) -- the leader's bike came or went
            return
        end
        if following[ped] then
            -- No script-task hash to poll for the follow mission: a long stall stands in.
            if stoppedSince[ped] and now - stoppedSince[ped] >= cfg().FollowStallMs then
                apply(ped, scene, now)
            end
            return
        end
    end
    if taskDropped(ped, DRIVE_WANDER_TASK) then apply(ped, scene, now) end
end

local function refreshVehicle(ped, scene, now)
    local vehicle = entityOf(scene.vehicle_net)
    if not vehicle then
        if not IsPedInAnyVehicle(ped, false) and idle(ped, now, Config.Population.WanderIdleMs) then
            apply(ped, scene, now)
        end
        return
    end
    if not IsPedInVehicle(ped, vehicle, false) then
        if vehicleLost[ped] or not taskDropped(ped, ENTER_TASK) then return end
        apply(ped, scene, now)
        return
    end
    vehicleLost[ped] = nil
    if scene.seat ~= -1 then return end
    refreshDriver(ped, scene, vehicle, now)
end

function HumalikeNpcScenesClient.Configure(ped, scene, state, now)
    if HumalikeNpcScenesClient.Incapacitated(ped) then return end
    if state.humalike_scene_held == true then
        applyHeld(ped, scene)
        return
    end
    apply(ped, scene, now)
end

function HumalikeNpcScenesClient.Refresh(ped, scene, state, now)
    if HumalikeNpcScenesClient.Incapacitated(ped) then return end
    if state.humalike_scene_held == true then
        applyHeld(ped, scene)
        return
    end
    if heldInit[ped] then
        heldInit[ped] = nil
        if not IsPedInAnyVehicle(ped, false) then ClearPedTasks(ped) end
        apply(ped, scene, now)
        return
    end
    if turnUntil[ped] then
        if now >= turnUntil[ped] then apply(ped, scene, now) end
        return
    end
    if roles[ped] ~= roleOf(scene) then
        apply(ped, scene, now)
        return
    end
    local archetype = scene.archetype
    if VEHICLE_ARCHETYPES[archetype] then
        refreshVehicle(ped, scene, now)
    elseif (archetype == 'walk' or archetype == 'run') and scene.slot ~= 0 then
        refreshFollower(ped, scene, now)
    else
        local threshold = SCENARIO_ARCHETYPES[archetype] and Config.Population.ScenarioIdleMs
            or Config.Population.WanderIdleMs
        if idle(ped, now, threshold) then apply(ped, scene, now) end
    end
end

-- After a hold or an action ends the crew's task is issued again from scratch.
function HumalikeNpcScenesClient.Reapply(ped, scene, state, now)
    heldInit[ped] = nil
    turnUntil[ped] = nil
    if state.humalike_scene_held == true then
        applyHeld(ped, scene)
        return
    end
    apply(ped, scene, now)
end

local registries = { turnUntil, turned, heldInit, stoppedSince, roles, following, enteredAt,
    vehicleLost }

function HumalikeNpcScenesClient.Forget(seen)
    for _, registry in ipairs(registries) do
        for ped in pairs(registry) do
            if not seen[ped] then registry[ped] = nil end
        end
    end
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for _, registry in ipairs(registries) do
        for ped in pairs(registry) do registry[ped] = nil end
    end
end)
