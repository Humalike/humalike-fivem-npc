
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

local function appendProjected(frame, seen, npcId, ped, entry, camera, maxDistanceSquared, height)
    if not ped or seen[ped] or not entry or not DoesEntityExist(ped) then return false end
    seen[ped] = true

    local coords = GetEntityCoords(ped)
    local dx, dy, dz = camera.x - coords.x, camera.y - coords.y, camera.z - coords.z
    local distanceSquared = dx * dx + dy * dy + dz * dz
    if distanceSquared <= 0.0 or distanceSquared > maxDistanceSquared then return false end
    local visible, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z + height)
    if visible then
        frame[#frame + 1] = {
            screenX,
            screenY,
            normalizedLanguage(entry),
            voiceMuted(npcId, entry) and 1 or 0,
        }
    end
    return true
end

local function appendCandidate(candidates, seen, npcId, ped, entry, camera, radiusSquared)
    if not ped or seen[ped] or not entry or not DoesEntityExist(ped) then return end
    seen[ped] = true
    local coords = GetEntityCoords(ped)
    local dx, dy, dz = camera.x - coords.x, camera.y - coords.y, camera.z - coords.z
    if dx * dx + dy * dy + dz * dz <= radiusSquared then
        candidates[#candidates + 1] = { npcId = npcId, ped = ped, entry = entry }
    end
end

local function nearbyCandidates(maxDistance, margin)
    local camera = GetGameplayCamCoord()
    local radius = maxDistance + margin
    local candidates, seen = {}, {}
    for npcId, ped in pairs(LoadedPeds or {}) do
        appendCandidate(candidates, seen, npcId, ped, KnownNpcs and KnownNpcs[npcId], camera,
            radius * radius)
    end
    for npcId, ped in pairs(AmbientPeds or {}) do
        appendCandidate(candidates, seen, npcId, ped, AmbientNpcEntries and AmbientNpcEntries[npcId], camera,
            radius * radius)
    end
    return candidates
end

local function buildCandidateFrame(candidates, maxDistance, height)
    local camera = GetGameplayCamCoord()
    local frame, seen = {}, {}
    local hasNearbyNpc = false
    for _, candidate in ipairs(candidates) do
        if appendProjected(frame, seen, candidate.npcId, candidate.ped, candidate.entry, camera,
                maxDistance * maxDistance, height) then
            hasNearbyNpc = true
        end
    end
    return frame, hasNearbyNpc
end

function HumaLikeNpcLabels.BuildFrame()
    local labels = labelConfig()
    local maxDistance = tonumber(labels.MaxDistance) or 14.0
    local maxDistanceSquared = maxDistance * maxDistance
    local height = tonumber(labels.Height) or 0.98
    local camera = GetGameplayCamCoord()
    local frame, seen = {}, {}
    local hasNearbyNpc = false

    for npcId, ped in pairs(LoadedPeds or {}) do
        if appendProjected(frame, seen, npcId, ped, KnownNpcs and KnownNpcs[npcId], camera, maxDistanceSquared, height) then
            hasNearbyNpc = true
        end
    end
    for npcId, ped in pairs(AmbientPeds or {}) do
        if appendProjected(frame, seen, npcId, ped, AmbientNpcEntries and AmbientNpcEntries[npcId], camera, maxDistanceSquared, height) then
            hasNearbyNpc = true
        end
    end

    return frame, hasNearbyNpc
end

-- The NUI drops its labels 250 ms after the last frame, so an unchanged
-- frame is repeated at this interval instead of every render tick.
local FRAME_HEARTBEAT_MS = 150
local FRAME_EPSILON = 0.0005 -- normalised screen units, under a pixel

local function sameFrame(frame, last)
    if not last or #frame ~= #last then return false end
    for index = 1, #frame do
        local a, b = frame[index], last[index]
        if a[3] ~= b[3] or a[4] ~= b[4] or math.abs(a[1] - b[1]) > FRAME_EPSILON
            or math.abs(a[2] - b[2]) > FRAME_EPSILON then return false end
    end
    return true
end

CreateThread(function()
    local hadVisibleLabels = false
    local candidates = {}
    local candidatesAt = -1000000
    local nextFrameAt = 0
    local lastFrame, lastSentAt = nil, 0
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
                candidates = nearbyCandidates(maxDistance,
                    math.max(0.0, tonumber(labels.CandidateMargin) or 3.0))
                candidatesAt = now
            end

            local renderFps = math.max(1, tonumber(labels.RenderFps) or 60)
            if now < nextFrameAt then
                Wait(0)
            else
                local frameInterval = math.max(1, math.floor(1000 / renderFps))
                nextFrameAt = math.max(now, nextFrameAt + frameInterval)
                local frame, hasNearbyNpc = buildCandidateFrame(candidates, maxDistance,
                    tonumber(labels.Height) or 0.98)
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
                    Wait(0)
                else
                    if hadVisibleLabels then
                        SendNUIMessage({ type = 'labels:clear' })
                        hadVisibleLabels = false
                        lastFrame = nil
                    end
                    Wait(hasNearbyNpc and 50 or 250)
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
