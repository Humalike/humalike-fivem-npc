HumalikeNpcDirectTargets = HumalikeNpcDirectTargets or {}

local REFRESH_MS = 100
-- With no NPC this close (and no target), the refresh runs this much slower:
-- nobody covers the distance to a gaze target between two refreshes.
local IDLE_DISTANCE = 10.0
local IDLE_REFRESH_MS = 400
local GAZE_DISTANCE = 3.0
local GAZE_MIN_DOT = math.cos(math.rad(20.0))
local MAX_TARGETS = 16

local observed = {}
local active = {}
local members = {}
local subscribers = {}
local locked = false
local available = false

local function copy(values)
    local result = {}
    for index, value in ipairs(values) do result[index] = value end
    return result
end

local function same(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        if left[index] ~= right[index] then return false end
    end
    return true
end

local function publish(values)
    if same(active, values) then return end
    active = copy(values)
    members = {}
    for _, npcId in ipairs(active) do members[npcId] = true end
    for _, subscriber in ipairs(subscribers) do subscriber(copy(active)) end
end

local function addGroup(result, seen, values)
    table.sort(values)
    for _, npcId in ipairs(values) do
        if not seen[npcId] and #result < MAX_TARGETS then
            seen[npcId] = true
            result[#result + 1] = npcId
        end
    end
end

local function followTarget(ped, localServerId)
    local params = ActionParams and ActionParams[ped] or nil
    return ActionControlledPeds and ActionControlledPeds[ped] == 'follow_player'
        and type(params) == 'table' and tonumber(params.player_id) == localServerId
end

-- Life and line of sight are asked of the game this often per NPC at most.
local ALIVE_CACHE_MS = 500
local LOS_CACHE_MS = 300
local aliveAt, aliveValue = {}, {}
local losAt, losValue, losFor = 0, false, nil

local function alive(track, now)
    if not track.exists then return false end
    local npcId = track.npcId
    if aliveAt[npcId] == nil or now - aliveAt[npcId] >= ALIVE_CACHE_MS then
        aliveAt[npcId], aliveValue[npcId] = now, not IsEntityDead(track.ped)
    end
    return aliveValue[npcId]
end

local function clearLineOfSight(playerPed, track, now)
    if losFor ~= track.npcId or now - losAt >= LOS_CACHE_MS then
        losFor, losAt = track.npcId, now
        losValue = HasEntityClearLosToEntity(playerPed, track.ped, 17)
    end
    return losValue
end

-- Positions come from the shared tracker; the game is asked only about the
-- player, the camera and the few NPCs that qualify.
local function calculate(listener)
    local now = GetGameTimer()
    local playerPed = PlayerPedId()
    local localServerId = GetPlayerServerId(PlayerId())
    local playerCoords = GetEntityCoords(playerPed)
    local player = HumalikeWorldCollector and HumalikeWorldCollector.latest or nil
    local playerVehicleNet = player and player.vehicle and player.vehicle.networkId or nil
    local forward = listener and listener.forward or nil
    local camera = nil -- read once, and only when somebody stands within gaze distance
    local followers, vehiclePeers = {}, {}
    local gaze, gazeDistance = nil, GAZE_DISTANCE + 1.0
    local nearby = false

    for npcId, track in pairs(HumalikeWorldTrack.tracks) do
        local voiceUnavailable = HumalikeNpcRuntimeControl
            and HumalikeNpcRuntimeControl.IsVoiceUnavailable(npcId)
        if not voiceUnavailable and track.exists then
            if followTarget(track.ped, localServerId) and alive(track, now) then
                followers[#followers + 1] = npcId
            end
            if playerVehicleNet and track.vehicleState
                and track.vehicleState.network_id == playerVehicleNet and alive(track, now) then
                vehiclePeers[#vehiclePeers + 1] = npcId
            end
            local px, py, pz = track.x - playerCoords.x, track.y - playerCoords.y, track.z - playerCoords.z
            local playerDistance = math.sqrt(px * px + py * py + pz * pz)
            if playerDistance <= IDLE_DISTANCE then nearby = true end
            if forward and playerDistance > 0.01 and playerDistance <= GAZE_DISTANCE
                and playerDistance < gazeDistance then
                camera = camera or GetGameplayCamCoord()
                local dx, dy, dz = track.x - camera.x, track.y - camera.y, track.z - camera.z
                local cameraDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
                local dot = cameraDistance > 0.01
                    and (dx * forward.x + dy * forward.y + dz * forward.z) / cameraDistance or -1.0
                if dot >= GAZE_MIN_DOT then gaze, gazeDistance = track, playerDistance end
            end
        end
    end

    local result, seen = {}, {}
    addGroup(result, seen, followers)
    addGroup(result, seen, vehiclePeers)
    if gaze and not seen[gaze.npcId] and #result < MAX_TARGETS and alive(gaze, now)
        and clearLineOfSight(playerPed, gaze, now) then
        result[#result + 1] = gaze.npcId
    end
    for npcId in pairs(aliveAt) do
        if not HumalikeWorldTrack.tracks[npcId] then aliveAt[npcId], aliveValue[npcId] = nil, nil end
    end
    return result, nearby or #result > 0
end

function HumalikeNpcDirectTargets.Subscribe(callback)
    if type(callback) ~= 'function' then return function() end end
    subscribers[#subscribers + 1] = callback
    callback(copy(active))
    local subscribed = true
    return function()
        if not subscribed then return end
        subscribed = false
        for index, value in ipairs(subscribers) do
            if value == callback then table.remove(subscribers, index) break end
        end
    end
end

function HumalikeNpcDirectTargets.Get()
    return copy(active)
end

function HumalikeNpcDirectTargets.Lock()
    locked = true
end

function HumalikeNpcDirectTargets.Unlock()
    if not locked then return end
    locked = false
    publish(observed)
end

function HumalikeNpcDirectTargets.SetAvailable(value)
    available = value == true
end

function HumalikeNpcDirectTargets.IsReady(npcId)
    return available and members[npcId] == true
end

function HumalikeNpcDirectTargets.IsExclusive()
    return available and #active > 0
end

-- True while an NPC is close enough (or already a target) to keep the fast refresh.
function HumalikeNpcDirectTargets.Refresh(listener)
    local nearby
    observed, nearby = calculate(listener)
    if not locked then publish(observed) end
    return nearby
end

CreateThread(function()
    local nearby = true
    while true do
        Wait(nearby and REFRESH_MS or IDLE_REFRESH_MS)
        local listener = HumalikeWorldCollector and HumalikeWorldCollector.listener or nil
        nearby = true
        if listener then nearby = HumalikeNpcDirectTargets.Refresh(listener) end
    end
end)
