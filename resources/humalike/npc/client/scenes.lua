HumalikeNpcScenesClient = HumalikeNpcScenesClient or {}

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
local TURN_MS = 1000 -- the anchor-facing turn before a corner scenario starts
local HOLD_MS = 2000
local BRAKE_ACTION = 27
local RUN_DISTANCE = 120.0
local RUN_ARRIVE = 8.0
local RUN_ATTEMPTS = 4
local RUN_RETRY_MS = 5000 -- between target searches when no pavement is found
local RUN_SPEED = 2.0
local WALK_SPEED = 1.0
local FOLLOW_STOP = 1.0
local DRIVE_SPEED = 12.0
local DRIVE_STYLE = 786603
local FOLLOW_DISTANCE = 6
local ENTER_TIMEOUT_MS = 15000 -- the enter task's own timeout; also the gap between attempts
local VEHICLE_STOPPED_SPEED = 0.5
-- A bike following its leader has no script-task hash to poll (only the
-- wander mission does), so a follower is re-issued after a long stall instead;
-- 30 s outlasts any red light.
local FOLLOW_STALL_MS = 30000
local MAX_SEAT = 7
local PAVEMENT_FLAGS = 2 | 4 | 8 -- GetSafeCoordForPed: not isolated, not interior, not water
local FOLLOW_TASK = 'SCRIPT_TASK_FOLLOW_TO_OFFSET_OF_ENTITY'
local ENTER_TASK = 'SCRIPT_TASK_ENTER_VEHICLE'
local DRIVE_WANDER_TASK = 'SCRIPT_TASK_VEHICLE_DRIVE_WANDER'

local idleSince = {}
local turnUntil = {}
local turned = {}
local heldInit = {}
local runTargets = {}
local runRetryAt = {}
local stoppedSince = {}
local roles = {}
local following = {}
local enteredAt = {}
local vehicleLost = {}

local function config()
    return Config.Population
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
    if IsPedUsingAnyScenario(ped) or not IsPedStopped(ped) then
        idleSince[ped] = nil
        return false
    end
    idleSince[ped] = idleSince[ped] or now
    return now - idleSince[ped] >= threshold
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
        0.0, speed, -1, FOLLOW_STOP, true)
end

local function runTarget(ped)
    local coords = GetEntityCoords(ped)
    for _ = 1, RUN_ATTEMPTS do
        local angle = math.random() * 2 * math.pi
        local found, safe = GetSafeCoordForPed(coords.x + RUN_DISTANCE * math.cos(angle),
            coords.y + RUN_DISTANCE * math.sin(angle), coords.z, true, PAVEMENT_FLAGS)
        if found and safe then return safe end
    end
    return nil
end

local function applyRun(ped, scene, now)
    if scene.slot ~= 0 then
        follow(ped, scene, RUN_SPEED)
        return
    end
    local target = runTarget(ped)
    runTargets[ped] = target
    if not target then
        -- One wander per failed search; the next search waits RUN_RETRY_MS.
        runRetryAt[ped] = now + RUN_RETRY_MS
        TaskWanderStandard(ped, 10.0, 10)
        return
    end
    runRetryAt[ped] = nil
    TaskGoStraightToCoord(ped, target.x, target.y, target.z, RUN_SPEED, -1, 0.0, 0.0)
end

local function runArrived(ped)
    local target = runTargets[ped]
    local coords = GetEntityCoords(ped)
    local dx, dy = coords.x - target.x, coords.y - target.y
    return dx * dx + dy * dy <= RUN_ARRIVE * RUN_ARRIVE
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

local function playerInside(vehicle)
    for seat = -1, MAX_SEAT do
        local occupant = GetPedInVehicleSeat(vehicle, seat)
        if occupant ~= 0 and IsPedAPlayer(occupant) then return true end
    end
    return false
end

-- A seat someone else took, or a player anywhere in the vehicle, ends the
-- ride for this body: it walks off once and is not sent back.
local function seatTaken(ped, vehicle, seat)
    local occupant = GetPedInVehicleSeat(vehicle, seat)
    return (occupant ~= 0 and occupant ~= ped) or playerInside(vehicle)
end

local function enter(ped, scene, vehicle, now)
    local seat = tonumber(scene.seat) or -1
    if seatTaken(ped, vehicle, seat) then
        vehicleLost[ped] = true
        TaskWanderStandard(ped, 10.0, 10)
        return
    end
    if enteredAt[ped] and now - enteredAt[ped] < ENTER_TIMEOUT_MS then return end
    enteredAt[ped] = now
    TaskEnterVehicle(ped, vehicle, ENTER_TIMEOUT_MS, seat, 1.0, 1, 0)
end

local function drive(ped, scene, vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    stoppedSince[ped] = nil
    if bikeFollower(scene) then
        local lead = leaderVehicle(scene)
        if lead then
            following[ped] = true
            TaskVehicleFollow(ped, vehicle, lead, DRIVE_STYLE, DRIVE_SPEED, FOLLOW_DISTANCE)
            return
        end
    end
    following[ped] = false
    TaskVehicleDriveWander(ped, vehicle, DRIVE_SPEED, DRIVE_STYLE)
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
    idleSince[ped] = now
    roles[ped] = roleOf(scene)
    local archetype = scene.archetype
    if SCENARIO_ARCHETYPES[archetype] then
        if not turned[ped] then
            turned[ped] = true
            turnUntil[ped] = now + TURN_MS
            TaskTurnPedToFaceCoord(ped, scene.ax, scene.ay, scene.az, TURN_MS)
            return
        end
        turnUntil[ped] = nil
        TaskStartScenarioInPlace(ped, scenarioFor(scene), 0, true)
    elseif archetype == 'walk' then
        if scene.slot == 0 then
            TaskWanderStandard(ped, 10.0, 10)
        else
            follow(ped, scene, WALK_SPEED)
        end
    elseif archetype == 'run' then
        applyRun(ped, scene, now)
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
    TaskVehicleTempAction(ped, vehicle, BRAKE_ACTION, HOLD_MS)
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
    TaskStandStill(ped, HOLD_MS)
end

-- A follower keeps its follow task until it drops; wandering without a
-- leader, it takes the leader up as soon as one is there.
local function refreshFollower(ped, scene, now)
    local leader = leaderOf(scene)
    if following[ped] then
        if not leader or taskDropped(ped, FOLLOW_TASK) then apply(ped, scene, now) end
        return
    end
    if leader or idle(ped, now, config().WanderIdleMs) then apply(ped, scene, now) end
end

local function refreshRunLeader(ped, scene, now)
    if not runTargets[ped] then
        if now >= (runRetryAt[ped] or 0) then apply(ped, scene, now) end
        return
    end
    if runArrived(ped) or idle(ped, now, config().WanderIdleMs) then apply(ped, scene, now) end
end

local function refreshDriver(ped, scene, vehicle, now)
    if GetEntitySpeed(vehicle) >= VEHICLE_STOPPED_SPEED then
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
            if stoppedSince[ped] and now - stoppedSince[ped] >= FOLLOW_STALL_MS then
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
        if not IsPedInAnyVehicle(ped, false) and idle(ped, now, config().WanderIdleMs) then
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
    if HumalikeNpcScenesClient.Incapacitated(ped) then
        idleSince[ped] = nil
        return
    end
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
    elseif archetype == 'run' then
        refreshRunLeader(ped, scene, now)
    else
        local threshold = SCENARIO_ARCHETYPES[archetype] and config().ScenarioIdleMs
            or config().WanderIdleMs
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

local registries = { idleSince, turnUntil, turned, heldInit, runTargets, runRetryAt, stoppedSince,
    roles, following, enteredAt, vehicleLost }

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
