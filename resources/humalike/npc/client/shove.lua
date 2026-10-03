HumalikeNpcShove = HumalikeNpcShove or {}
local pending = {}
local lastReport = {}
local lastDamaged = {}

local function config()
    return Config.Shove
end

-- combat.lua stamps every hit the player lands so a punch is never also a shove.
function HumalikeNpcShove.NoteDamage(ped, now)
    lastDamaged[ped] = now
end

local function excluded(ped, npcId, now)
    if not DoesEntityExist(ped) or IsPedAPlayer(ped) or IsEntityDead(ped) then return true end
    if HumalikeDownedState and HumalikeDownedState(npcId) then return true end
    if lastDamaged[ped] and now - lastDamaged[ped] <= config().MeleeIgnoreMs then return true end
    -- A ped in melee is throwing the punch; a follower brushing past is no shove.
    if IsPedInMeleeCombat(ped) then return true end
    local action = ActionControlledPeds and ActionControlledPeds[ped] or nil
    return action == 'punch' or action == 'follow_player'
end

local function towards(velocity, from, to)
    return velocity.x * (to.x - from.x) + velocity.y * (to.y - from.y) > 0
end

local function due(ped, now)
    local previous = lastReport[ped]
    return not previous or now - previous >= config().ReportGapMs
end

local function report(ped, npcId, intensity, now)
    lastReport[ped] = now
    local entry = AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
    HumalikeDebug('npc %s shoved (%s)', npcId, intensity)
    TriggerServerEvent('humalike:npc:npcShoved', npcId, entry and entry.entity_id or nil,
        intensity)
end

local function forgetStale(now)
    local forgetAfter = config().ForgetAfterMs
    for ped, at in pairs(lastReport) do
        if now - at > forgetAfter then lastReport[ped] = nil end
    end
    for ped, at in pairs(lastDamaged) do
        if now - at > forgetAfter then lastDamaged[ped] = nil end
    end
end

-- A touch is held for KnockdownWindowMs and reported once with its final intensity.
local function settle(now)
    local reported = 0
    for ped, contact in pairs(pending) do
        if not DoesEntityExist(ped) then
            pending[ped] = nil
        else
            if IsPedRagdoll(ped) and not contact.ragdolled then contact.fell = true end
            if now - contact.since >= config().KnockdownWindowMs then
                pending[ped] = nil
                if not excluded(ped, contact.npc_id, now) then
                    report(ped, contact.npc_id, contact.fell and 'knocked_down' or 'bump', now)
                    reported = reported + 1
                end
            end
        end
    end
    return reported
end

-- Only registered peds can carry a HumaLike mind, and only the ones the
-- tracker puts within reach can be touched; the pool is never scanned.
local function eachNearPed(maxDistance, callback)
    local max2 = maxDistance * maxDistance
    for npcId, track in pairs(HumalikeWorldTrack.tracks) do
        if track.exists and track.dist2 <= max2 then callback(npcId, track) end
    end
end

function HumalikeNpcShove.Tick(now)
    forgetStale(now)
    local reported = settle(now)
    local cfg = config()
    -- Nobody within reach: the player's own state is not worth asking for.
    if not HumalikeWorldTrack.AnyWithin(cfg.MaxDistance) then return reported end
    local playerPed = PlayerPedId()
    if playerPed == 0 or not DoesEntityExist(playerPed) then return reported end
    -- A still player shoves nobody: the speed is asked before anything else.
    if GetEntitySpeed(playerPed) < cfg.MinSpeed or IsPedInAnyVehicle(playerPed, false)
        or IsEntityDead(playerPed) or IsPedRagdoll(playerPed) or IsPedInMeleeCombat(playerPed) then
        return reported
    end
    local origin = GetEntityCoords(playerPed)
    local velocity = GetEntityVelocity(playerPed)
    eachNearPed(cfg.MaxDistance, function(npcId, track)
        local ped = track.ped
        if not pending[ped] and due(ped, now) and not excluded(ped, npcId, now)
            and IsEntityTouchingEntity(playerPed, ped)
            and towards(velocity, origin, track) then
            pending[ped] = { since = now, npc_id = npcId, ragdolled = IsPedRagdoll(ped) }
        end
    end)
    return reported
end

-- With nobody in reach and no contact pending the detector sleeps longer.
local IDLE_TICK_MS = 500

CreateThread(function()
    while true do
        local busy = next(pending) ~= nil or HumalikeWorldTrack.AnyWithin(config().MaxDistance)
        Wait(busy and config().TickMs or IDLE_TICK_MS)
        HumalikeNpcShove.Tick(GetGameTimer())
    end
end)
