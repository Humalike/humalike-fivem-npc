HumalikeNpcDirectTargets = HumalikeNpcDirectTargets or {}

local REFRESH_MS = 100
local GAZE_DISTANCE = 3.0
local GAZE_MIN_DOT = math.cos(math.rad(20.0))
local MAX_TARGETS = 16

local observed = {}
local active = {}
local members = {}
local subscribers = {}
local locked = false
local available = false
local lastRefreshAt = -REFRESH_MS

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

local function calculate(listener)
    local playerPed = PlayerPedId()
    local playerVehicle = GetVehiclePedIsIn(playerPed, false)
    local localServerId = GetPlayerServerId(PlayerId())
    local playerCoords = GetEntityCoords(playerPed)
    local camera = GetGameplayCamCoord()
    local forward = listener and listener.forward or nil
    local followers, vehiclePeers = {}, {}
    local gazeId, gazeDistance = nil, GAZE_DISTANCE + 1.0

    for npcId, entry in pairs(HumalikeWorldRegistry.entries) do
        local ped = entry.entity
        if ped and ped > 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
            if followTarget(ped, localServerId) then followers[#followers + 1] = npcId end
            if playerVehicle ~= 0 and GetVehiclePedIsIn(ped, false) == playerVehicle then
                vehiclePeers[#vehiclePeers + 1] = npcId
            end
            if forward then
                local coords = GetEntityCoords(ped)
                local px, py, pz = coords.x - playerCoords.x, coords.y - playerCoords.y, coords.z - playerCoords.z
                local playerDistance = math.sqrt(px * px + py * py + pz * pz)
                if playerDistance > 0.01 and playerDistance <= GAZE_DISTANCE then
                    local dx, dy, dz = coords.x - camera.x, coords.y - camera.y, coords.z - camera.z
                    local cameraDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
                    local dot = cameraDistance > 0.01
                        and (dx * forward.x + dy * forward.y + dz * forward.z) / cameraDistance or -1.0
                    if dot >= GAZE_MIN_DOT and playerDistance < gazeDistance then
                        gazeId, gazeDistance = npcId, playerDistance
                    end
                end
            end
        end
    end

    local result, seen = {}, {}
    addGroup(result, seen, followers)
    addGroup(result, seen, vehiclePeers)
    if gazeId and not seen[gazeId] and #result < MAX_TARGETS then
        local gazePed = HumalikeWorldRegistry.entries[gazeId].entity
        if HasEntityClearLosToEntity(playerPed, gazePed, 17) then result[#result + 1] = gazeId end
    end
    return result
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

AddEventHandler('humalike:world:listener', function(listener)
    local now = GetGameTimer()
    if now - lastRefreshAt < REFRESH_MS then return end
    lastRefreshAt = now
    observed = calculate(listener)
    if not locked then publish(observed) end
end)
