
NpcPoses = {} -- npc_id -> pose action key
local poseOrder = {}
local MAX_TRACKED_POSES = 512
local poseTargets = {}
local aloneSince = {}

local POSES = { kneel = true, hands_up = true, start_dancing = true }
local CLEARS = {
    stand_up = true,
    interrupt_animation = true,
    follow_player = true,
    hold_position = true,
    release_movement = true,
    punch = true,
    enter_vehicle = true,
    exit_vehicle = true,
    walk_away = true,
}
local REPLAY_INTERVAL_MS = 1500
local REPLAY_MAX_ATTEMPTS = 10

local function forget(npcId)
    poseTargets[npcId] = nil
    aloneSince[npcId] = nil
    if NpcPoses[npcId] == nil then return end
    NpcPoses[npcId] = nil
    for index, tracked in ipairs(poseOrder) do
        if tracked == npcId then
            table.remove(poseOrder, index)
            break
        end
    end
end

local function remember(npcId, actionKey)
    if NpcPoses[npcId] == nil then
        poseOrder[#poseOrder + 1] = npcId
        if #poseOrder > MAX_TRACKED_POSES then
            local oldest = table.remove(poseOrder, 1)
            NpcPoses[oldest] = nil
        end
    end
    NpcPoses[npcId] = actionKey
end
function RecordNpcPose(npcId, actionKey, target)
    if POSES[actionKey] then
        remember(npcId, actionKey)
        poseTargets[npcId] = target
        aloneSince[npcId] = nil
    elseif CLEARS[actionKey] then
        forget(npcId)
    end
end
function ForgetNpcPose(npcId)
    forget(npcId)
end
function RefreshNpcPoseTarget(npcId, target)
    if NpcPoses[npcId] ~= nil then
        poseTargets[npcId] = target
        aloneSince[npcId] = nil
    end
end
local function poseBody(npcId)
    local target = poseTargets[npcId]
    if target and target.kind == 'ambient' then
        if type(ValidateAmbientActionTarget) ~= 'function' then return nil end
        local _, entity = ValidateAmbientActionTarget(target)
        return entity
    end
    local npc = NpcRegistry and NpcRegistry[npcId] or nil
    local entity = npc and npc.entity_id or nil
    if type(entity) ~= 'number' or entity <= 0 then return nil end
    return entity
end
function HumalikePoseBody(npcId)
    return poseBody(npcId)
end

local function nearbyPlayerSamples()
    local samples = {}
    for _, playerId in ipairs(GetPlayers()) do
        local ped = GetPlayerPed(playerId)
        if ped and ped ~= 0 and DoesEntityExist(ped) then
            samples[#samples + 1] = GetEntityCoords(ped)
        end
    end
    return samples
end

local function anyoneNear(entity, radius, players)
    local coords = GetEntityCoords(entity)
    local radiusSquared = radius * radius
    for _, playerCoords in ipairs(players) do
        local dx, dy, dz = playerCoords.x - coords.x, playerCoords.y - coords.y,
            playerCoords.z - coords.z
        if dx * dx + dy * dy + dz * dz <= radiusSquared then return true end
    end
    return false
end
local function releasePose(npcId, entity)
    local target = poseTargets[npcId]
    local pose = NpcPoses[npcId]
    forget(npcId)
    if entity and DoesEntityExist(entity) then
        Entity(entity).state:set('humalike_action', nil, true)
    end
    local released = false
    if target and type(HumalikeReleasePose) == 'function' then
        released = HumalikeReleasePose(target) == true
    end
    HumalikeDebug('npc %s left its %s: nobody near it (stand_up %s)', npcId, tostring(pose),
        released and 'delivered' or 'undeliverable')
end
function HumalikePoseAbandonSweep()
    local now = GetGameTimer()
    local radius = Config.PoseAbandonRadius or 60.0
    local abandonAfter = Config.PoseAbandonMs or 120000
    local abandoned = {}
    local players
    for npcId in pairs(NpcPoses) do
        local entity = poseBody(npcId)
        local exists = entity and DoesEntityExist(entity)
        if exists then players = players or nearbyPlayerSamples() end
        if exists and anyoneNear(entity, radius, players) then
            aloneSince[npcId] = nil
        else
            aloneSince[npcId] = aloneSince[npcId] or now
            if now - aloneSince[npcId] >= abandonAfter then
                abandoned[#abandoned + 1] = { npc_id = npcId, entity = entity }
            end
        end
    end
    for _, item in ipairs(abandoned) do releasePose(item.npc_id, item.entity) end
end

CreateThread(function()
    while true do
        Wait(Config.PoseAbandonTickMs or 5000)
        HumalikePoseAbandonSweep()
    end
end)
function ReplayNpcPoseWhenReady(npcId, pose, stillWanted, send)
    -- Retry while a new owner streams the body; fixed delays lose slow migrations.
    local attempts = 0
    local function attempt()
        attempts = attempts + 1
        if NpcPoses[npcId] ~= pose or not stillWanted() then return end
        if send() then return end
        if attempts >= REPLAY_MAX_ATTEMPTS then
            HumalikeDebug('pose replay for npc %s (%s) gave up after %d attempts',
                npcId, pose, attempts)
            return
        end
        SetTimeout(REPLAY_INTERVAL_MS, attempt)
    end
    SetTimeout(REPLAY_INTERVAL_MS, attempt)
end
