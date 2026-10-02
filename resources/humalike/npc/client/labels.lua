
HumaLikeNpcLabels = HumaLikeNpcLabels or {}

local function labelConfig()
    return Config.NpcLabels or {}
end

local languageCache = setmetatable({}, { __mode = 'k' })

local function directTargetReady(npcId)
    return HumalikeNpcDirectTargets
        and HumalikeNpcDirectTargets.IsReady(npcId) == true
end

local function voiceMuted(npcId, entry)
    if HumalikeNpcRuntimeControl
        and HumalikeNpcRuntimeControl.IsVoiceUnavailable(npcId) then return true end
    local ready = directTargetReady(npcId)
    if HumalikeNpcDirectTargets and HumalikeNpcDirectTargets.IsExclusive
        and HumalikeNpcDirectTargets.IsExclusive() == true then
        return not ready
    end
    return entry.voice_muted == true and not ready
end

local function normalizedLanguage(entry)
    local raw = entry and entry.language or nil
    local cached = entry and languageCache[entry] or nil
    if cached and cached.raw == raw then return cached.value end
    local value = HumaLikeNpcLabels.NormalizeLanguage(raw)
    if entry then languageCache[entry] = { raw = raw, value = value } end
    return value
end

function HumaLikeNpcLabels.NormalizeLanguage(language)
    if type(language) ~= 'string' or language == '' then return false end

    local labels = labelConfig()
    local key = string.lower(language)
    local baseKey = key:match('^([a-z0-9]+)') or key
    local defaultKey = string.lower(labels.DefaultLanguage or 'en')
    local defaultBase = defaultKey:match('^([a-z0-9]+)') or defaultKey
    if not labels.ShowDefaultLanguage and (key == defaultKey or baseKey == defaultBase) then
        return false
    end

    return labels.LanguageLabels
        and (labels.LanguageLabels[key] or labels.LanguageLabels[baseKey])
        or baseKey
end

local function entryOf(npcId)
    local entry = KnownNpcs and KnownNpcs[npcId]
    if entry then return entry end
    return AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
end

-- The gameplay camera trails the player by a few metres; candidates are taken
-- from the tracker's player distance with that much slack on top of the margin.
local CAMERA_SLACK = 4.0

-- Candidates come from the shared tracker: no native per NPC. A ped with a
-- label entry but no track (not registered yet) is checked directly.
local function nearbyCandidates(maxDistance, margin)
    local radius = maxDistance + margin
    local candidates, seen = {}, {}
    local tracks = HumalikeWorldTrack and HumalikeWorldTrack.tracks or nil
    if tracks then
        local trackRadius2 = (radius + CAMERA_SLACK) * (radius + CAMERA_SLACK)
        for npcId, track in pairs(tracks) do
            if track.exists and track.dist2 <= trackRadius2 then
                local entry = entryOf(npcId)
                local index = seen[track.ped]
                if entry and index and KnownNpcs and KnownNpcs[npcId] and not KnownNpcs[candidates[index].npcId] then
                    -- One ped under two ids: the persistent registration labels it.
                    candidates[index] = { npcId = npcId, ped = track.ped, entry = entry, track = track }
                elseif entry and not index then
                    candidates[#candidates + 1] = { npcId = npcId, ped = track.ped, entry = entry, track = track }
                    seen[track.ped] = #candidates
                end
            end
        end
    end
    local camera = nil
    local function direct(npcId, ped, entry)
        if not ped or seen[ped] or not entry or (tracks and tracks[npcId]) or not DoesEntityExist(ped) then return end
        seen[ped] = #candidates + 1
        camera = camera or GetGameplayCamCoord()
        local coords = GetEntityCoords(ped)
        local dx, dy, dz = camera.x - coords.x, camera.y - coords.y, camera.z - coords.z
        if dx * dx + dy * dy + dz * dz <= radius * radius then
            candidates[#candidates + 1] = { npcId = npcId, ped = ped, entry = entry }
        end
    end
    for npcId, ped in pairs(LoadedPeds or {}) do direct(npcId, ped, KnownNpcs and KnownNpcs[npcId]) end
    for npcId, ped in pairs(AmbientPeds or {}) do direct(npcId, ped, AmbientNpcEntries and AmbientNpcEntries[npcId]) end
    return candidates
end

-- Projection of one candidate. The screen position is recomputed when the
-- camera moved or the ped did; a still scene reuses the last one.
local function project(candidate, camera, cameraMoved, maxDistanceSquared, height)
    local ped = candidate.ped
    local track = candidate.track
    local x, y, z
    if track and track.speed <= 0.0 then
        x, y, z = track.x, track.y, track.z
    else
        if not DoesEntityExist(ped) then return false end
        local coords = GetEntityCoords(ped)
        x, y, z = coords.x, coords.y, coords.z
    end
    local dx, dy, dz = camera.x - x, camera.y - y, camera.z - z
    local distanceSquared = dx * dx + dy * dy + dz * dz
    if distanceSquared <= 0.0 or distanceSquared > maxDistanceSquared then return false end
    local pedMoved = x ~= candidate.lastX or y ~= candidate.lastY or z ~= candidate.lastZ
    if cameraMoved or pedMoved or candidate.visible == nil then
        candidate.lastX, candidate.lastY, candidate.lastZ = x, y, z
        candidate.visible, candidate.screenX, candidate.screenY = World3dToScreen2d(x, y, z + height)
    end
    return true
end

local function buildCandidateFrame(candidates, camera, cameraMoved, maxDistance, height)
    local frame = {}
    local hasNearbyNpc = false
    for _, candidate in ipairs(candidates) do
        if project(candidate, camera, cameraMoved, maxDistance * maxDistance, height) then
            hasNearbyNpc = true
            if candidate.visible then
                frame[#frame + 1] = {
                    candidate.screenX,
                    candidate.screenY,
                    normalizedLanguage(candidate.entry),
                    voiceMuted(candidate.npcId, candidate.entry) and 1 or 0,
                    candidate.npcId,
                }
            end
        end
    end
    return frame, hasNearbyNpc
end

-- One frame straight from the game, for callers outside the render loop.
function HumaLikeNpcLabels.BuildFrame()
    local labels = labelConfig()
    local maxDistance = tonumber(labels.MaxDistance) or 14.0
    local candidates = nearbyCandidates(maxDistance, 0.0)
    return buildCandidateFrame(candidates, GetGameplayCamCoord(), true, maxDistance,
        tonumber(labels.Height) or 0.98)
end

-- An unchanged frame is repeated at this interval; the NUI drops labels it
-- has not heard about for three seconds.
local FRAME_HEARTBEAT_MS = 1000
local FRAME_EPSILON = 0.0005 -- normalised screen units, under a pixel
-- With no NPC within MaxDistance + CandidateMargin the thread rechecks this often;
-- the margin covers the walk in between, so a label shows up at most this late.
local IDLE_RECHECK_MS = 250
local CAMERA_MOVE_EPSILON = 0.005 -- metres
local CAMERA_TURN_EPSILON = 0.02  -- degrees

local function sameFrame(frame, last)
    if not last or #frame ~= #last then return false end
    for index = 1, #frame do
        local a, b = frame[index], last[index]
        if a[3] ~= b[3] or a[4] ~= b[4] or a[5] ~= b[5] or math.abs(a[1] - b[1]) > FRAME_EPSILON
            or math.abs(a[2] - b[2]) > FRAME_EPSILON then return false end
    end
    return true
end

local function cameraMovedSince(camera, rotation, last)
    if not last then return true end
    return math.abs(camera.x - last.x) > CAMERA_MOVE_EPSILON
        or math.abs(camera.y - last.y) > CAMERA_MOVE_EPSILON
        or math.abs(camera.z - last.z) > CAMERA_MOVE_EPSILON
        or math.abs(rotation.x - last.pitch) > CAMERA_TURN_EPSILON
        or math.abs(rotation.z - last.yaw) > CAMERA_TURN_EPSILON
end

CreateThread(function()
    local hadVisibleLabels = false
    local candidates = {}
    local candidatesAt = -1000000
    local nextFrameAt = 0
    local lastFrame, lastSentAt = nil, 0
    local lastCamera = nil
    while true do
        local labels = labelConfig()
        if labels.Enabled == false then
            if hadVisibleLabels then
                SendNUIMessage({ type = 'labels:clear' })
                hadVisibleLabels = false
            end
            Wait(1000)
        else
            local now = GetGameTimer()
            local maxDistance = tonumber(labels.MaxDistance) or 14.0
            local refreshMs = math.max(50, tonumber(labels.CandidateRefreshMs) or 200)
            if now - candidatesAt >= refreshMs then
                local previous = {}
                for _, candidate in ipairs(candidates) do previous[candidate.npcId] = candidate end
                candidates = nearbyCandidates(maxDistance,
                    math.max(0.0, tonumber(labels.CandidateMargin) or 3.0))
                for _, candidate in ipairs(candidates) do
                    local old = previous[candidate.npcId]
                    if old and old.ped == candidate.ped then
                        candidate.lastX, candidate.lastY, candidate.lastZ = old.lastX, old.lastY, old.lastZ
                        candidate.visible, candidate.screenX, candidate.screenY = old.visible, old.screenX, old.screenY
                    end
                end
                candidatesAt = now
            end

            local renderFps = math.max(1, tonumber(labels.RenderFps) or 30)
            if #candidates == 0 then
                if hadVisibleLabels then
                    SendNUIMessage({ type = 'labels:clear' })
                    hadVisibleLabels = false
                    lastFrame = nil
                end
                candidatesAt = -1000000 -- rescan on wake
                lastCamera = nil
                Wait(IDLE_RECHECK_MS)
            elseif now < nextFrameAt then
                Wait(nextFrameAt - now)
            else
                local frameInterval = math.max(1, math.floor(1000 / renderFps))
                nextFrameAt = math.max(now, nextFrameAt + frameInterval)
                local camera, rotation = GetGameplayCamCoord(), GetGameplayCamRot(2)
                local cameraMoved = cameraMovedSince(camera, rotation, lastCamera)
                if cameraMoved then
                    lastCamera = { x = camera.x, y = camera.y, z = camera.z, pitch = rotation.x, yaw = rotation.z }
                end
                local frame, hasNearbyNpc = buildCandidateFrame(candidates, camera, cameraMoved,
                    maxDistance, tonumber(labels.Height) or 0.98)
                if #frame > 0 then
                    if now - lastSentAt >= FRAME_HEARTBEAT_MS or not sameFrame(frame, lastFrame) then
                        SendNUIMessage({
                            type = 'labels:frame',
                            scale = tonumber(labels.Scale) or 1.0,
                            labels = frame,
                        })
                        lastFrame, lastSentAt = frame, now
                    end
                    hadVisibleLabels = true
                    Wait(math.max(0, nextFrameAt - GetGameTimer()))
                else
                    if hadVisibleLabels then
                        SendNUIMessage({ type = 'labels:clear' })
                        hadVisibleLabels = false
                        lastFrame = nil
                    end
                    Wait(hasNearbyNpc and 50 or IDLE_RECHECK_MS)
                end
            end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SendNUIMessage({ type = 'labels:clear' })
    end
end)
