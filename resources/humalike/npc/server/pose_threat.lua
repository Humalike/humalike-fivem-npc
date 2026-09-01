
local THREAT_POSES = { hands_up = true, kneel = true }
local watch = {}

local function config()
    return Config.PoseThreat or {}
end

local unarmed = GetHashKey('WEAPON_UNARMED') % 4294967296

local function isArmed(ped)
    local ok, weapon = pcall(GetSelectedPedWeapon, ped)
    if not ok or type(weapon) ~= 'number' then return false end
    return weapon % 4294967296 ~= unarmed
end
local function playerSamples()
    local samples = {}
    for _, playerId in ipairs(GetPlayers()) do
        local id = tonumber(playerId)
        local ped = GetPlayerPed(playerId)
        if id and ped and ped ~= 0 and DoesEntityExist(ped) then
            samples[#samples + 1] = {
                id = id,
                coords = GetEntityCoords(ped),
                armed = isArmed(ped),
                loaded = HumalikePlayer.IsCharacterLoaded(id),
            }
        end
    end
    return samples
end

local function scanScene(coords, radius, players)
    local armed = false
    local radiusSquared = radius * radius
    local reporter, reporterDistanceSquared = nil, radiusSquared
    for _, player in ipairs(players) do
        local dx, dy, dz = player.coords.x - coords.x, player.coords.y - coords.y,
            player.coords.z - coords.z
        local distanceSquared = dx * dx + dy * dy + dz * dz
        if distanceSquared <= radiusSquared then
            if player.armed then armed = true end
            if distanceSquared <= reporterDistanceSquared and player.loaded then
                reporter, reporterDistanceSquared = player.id, distanceSquared
            end
        end
    end
    return armed, reporter
end

local function post(observation, delay, attempt)
    attempt = attempt or 1
    HumalikeHttp.PostAction('ingest_world_event', observation, function(ok, status, body)
        if ok and body and body.ok == true then return end
        if attempt < 5 and (status == 0 or status >= 500) then
            SetTimeout(delay, function() post(observation, delay * 2, attempt + 1) end)
        end
    end)
end

local function notifyThreatSubsided(npcId, entity, reporter)
    local lease = AmbientNpcLeases and AmbientNpcLeases[entity] or nil
    post({
        fivem_session_id = reporter,
        source_event_id = HumalikeHttp.NextSourceEventId(reporter),
        occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        event = {
            type = 'threat_subsided',
            npc_id = npcId,
            lease_token = lease and lease.lease_token or nil,
        },
    }, 1000)
    HumalikeDebug('npc %s: threat subsided (reported by %s)', npcId, tostring(reporter))
end
function HumalikePoseThreatSweep()
    if config().Enabled == false then return end
    local now = GetGameTimer()
    local radius = tonumber(config().Radius) or 30.0
    local clearAfter = tonumber(config().ClearMs) or 60000
    local players
    for npcId in pairs(watch) do
        if not THREAT_POSES[NpcPoses[npcId]] then watch[npcId] = nil end
    end
    for npcId, pose in pairs(NpcPoses) do
        if THREAT_POSES[pose] then
            local entity = type(HumalikePoseBody) == 'function' and HumalikePoseBody(npcId) or nil
            if not entity or not DoesEntityExist(entity) then
                watch[npcId] = nil
            else
                players = players or playerSamples()
                local entry = watch[npcId] or { armedLastAt = now }
                watch[npcId] = entry
                local armed, reporter = scanScene(GetEntityCoords(entity), radius, players)
                if armed then
                    entry.armedLastAt = now
                    entry.notified = nil
                elseif now - entry.armedLastAt >= clearAfter and not entry.notified then
                    if reporter then
                        entry.notified = true
                        notifyThreatSubsided(npcId, entity, reporter)
                    end
                end
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(Config.PoseThreatTickMs or 2500)
        HumalikePoseThreatSweep()
    end
end)
