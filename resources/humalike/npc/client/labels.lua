
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
        camera = camera or HumalikePulse.CamCoord()
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
        -- A tracked ped that vanished since its last sample reads as the origin,
        -- which the distance below rejects; an untracked one is asked for.
        if not track and not DoesEntityExist(ped) then return false end
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
            -- A projection that is not a number is left out: one bad number
            -- would void the JSON of the whole pulse.
            if candidate.visible and candidate.screenX == candidate.screenX
                and candidate.screenY == candidate.screenY then
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
    return buildCandidateFrame(candidates, HumalikePulse.CamCoord(), true, maxDistance,
        tonumber(labels.Height) or 0.98)
end

-- An unchanged frame is repeated on every heartbeat of the pulse; the NUI
-- drops labels it has not heard about for three seconds.
local FRAME_HEARTBEAT_MS = 1000
local FRAME_EPSILON = 0.001 -- normalised screen units, about a pixel
-- With no NPC within MaxDistance + CandidateMargin the job rechecks this often;
-- the margin covers the walk in between, so a label shows up at most this late.
local IDLE_RECHECK_MS = 250
-- The idle camera breathes; below these the scene counts as still.
local CAMERA_MOVE_EPSILON = 0.02 -- metres
local CAMERA_TURN_EPSILON = 0.1  -- degrees
local CAMERA_ZOOM_EPSILON = 0.05 -- degrees of field of view

local function sameFrame(frame, last)
    if not last or #frame ~= #last then return false end
    for index = 1, #frame do
        local a, b = frame[index], last[index]
        if a[3] ~= b[3] or a[4] ~= b[4] or a[5] ~= b[5] or math.abs(a[1] - b[1]) > FRAME_EPSILON
            or math.abs(a[2] - b[2]) > FRAME_EPSILON then return false end
    end
    return true
end

-- A frame goes to the NUI as `{"type":"labels:frame","scale":s,"labels":[[x,y,lang,muted,"id"],...]}`,
-- written by hand: the generic encoder cost more than the rest of a render.
local function jsonString(value)
    value = tostring(value)
    if value:find('[%c"\\]') then
        value = value:gsub('[%c"\\]', function(char)
            if char == '"' then return '\\"' end
            if char == '\\' then return '\\\\' end
            return ('\\u%04x'):format(char:byte())
        end)
    end
    return '"' .. value .. '"'
end

local function encodeFrame(frame, scale)
    local parts = {}
    for index, label in ipairs(frame) do
        parts[index] = ('[%.4f,%.4f,%s,%d,%s]'):format(label[1], label[2],
            label[3] and jsonString(label[3]) or 'false', label[4], jsonString(label[5]))
    end
    return ('{"type":"labels:frame","scale":%.3f,"labels":[%s]}'):format(scale, table.concat(parts, ','))
end
HumaLikeNpcLabels.EncodeFrame = encodeFrame

local function anyMoving(candidates)
    for _, candidate in ipairs(candidates) do
        local track = candidate.track
        if not track or track.speed > 0.0 then return true end
    end
    return false
end

-- A zoom (a scope, an aim) moves every label without moving the camera.
local function cameraMovedSince(camera, rotation, fov, last)
    if not last then return true end
    return math.abs(camera.x - last.x) > CAMERA_MOVE_EPSILON
        or math.abs(camera.y - last.y) > CAMERA_MOVE_EPSILON
        or math.abs(camera.z - last.z) > CAMERA_MOVE_EPSILON
        or math.abs(rotation.x - last.pitch) > CAMERA_TURN_EPSILON
        or math.abs(rotation.z - last.yaw) > CAMERA_TURN_EPSILON
        or math.abs(fov - last.fov) > CAMERA_ZOOM_EPSILON
end

local CLEAR = '{"type":"labels:clear"}'
local hadVisibleLabels = false
local candidates = {}
local candidatesDue = -1000000
local lastFrame, lastSentBeat = nil, nil
local lastCamera = nil

local function clear()
    if not hadVisibleLabels then return end
    HumalikePulse.Send(CLEAR)
    hadVisibleLabels = false
    lastFrame = nil
end

-- One pass of the label loop; returns the milliseconds until the next one.
-- `due` is the pulse's schedule time: the candidate refresh is counted on it.
function HumaLikeNpcLabels.Render(_, due)
    local labels = labelConfig()
    if labels.Enabled == false then
        clear()
        return 1000
    end
    local maxDistance = tonumber(labels.MaxDistance) or 14.0
    local refreshMs = math.max(50, tonumber(labels.CandidateRefreshMs) or 200)
    if due - candidatesDue >= refreshMs then
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
        candidatesDue = due
    end

    if #candidates == 0 then
        clear()
        candidatesDue = -1000000 -- rescan on the next pass
        lastCamera = nil
        return IDLE_RECHECK_MS
    end

    local renderFps = math.max(1, tonumber(labels.RenderFps) or 30)
    local camera, rotation = HumalikePulse.CamCoord(), HumalikePulse.CamRot()
    local fov = GetFinalRenderedCamFov()
    local cameraMoved = cameraMovedSince(camera, rotation, fov, lastCamera)
    if cameraMoved then
        lastCamera = lastCamera or {}
        lastCamera.x, lastCamera.y, lastCamera.z = camera.x, camera.y, camera.z
        lastCamera.pitch, lastCamera.yaw, lastCamera.fov = rotation.x, rotation.z, fov
    end
    local beat = HumalikePulse.Beat(FRAME_HEARTBEAT_MS)
    local heartbeat = beat ~= lastSentBeat
    -- A still camera over still peds: the last frame still holds.
    if cameraMoved or lastFrame == nil or heartbeat or anyMoving(candidates) then
        local frame = buildCandidateFrame(candidates, camera, cameraMoved,
            maxDistance, tonumber(labels.Height) or 0.98)
        if #frame > 0 then
            if heartbeat or not sameFrame(frame, lastFrame) then
                HumalikePulse.Send(encodeFrame(frame, tonumber(labels.Scale) or 1.0))
                lastFrame, lastSentBeat = frame, beat
            end
            hadVisibleLabels = true
        else
            clear()
        end
    end
    return math.max(1, math.floor(1000 / renderFps))
end

HumalikePulse.Every('labels', IDLE_RECHECK_MS, HumaLikeNpcLabels.Render, 60)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        SendNUIMessage({ type = 'labels:clear' })
    end
end)
