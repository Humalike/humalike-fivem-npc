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

-- Only registry peds can carry a HumaLike mind; the pool is never scanned.
local function eachOwnPed(callback)
    for npcId, ped in pairs(AmbientPeds or {}) do callback(npcId, ped) end
    for npcId, ped in pairs(LoadedPeds or {}) do
        if not (AmbientPeds and AmbientPeds[npcId] == ped) then callback(npcId, ped) end
    end
end

function HumalikeNpcShove.Tick(now)
    forgetStale(now)
    local playerPed = PlayerPedId()
    if playerPed == 0 or not DoesEntityExist(playerPed) then return 0 end
    local reported = settle(now)
    local cfg = config()
    if IsPedInAnyVehicle(playerPed, false) or IsEntityDead(playerPed) or IsPedRagdoll(playerPed)
        or IsPedInMeleeCombat(playerPed) or GetEntitySpeed(playerPed) < cfg.MinSpeed then
        return reported
    end
    local origin = GetEntityCoords(playerPed)
    local velocity = GetEntityVelocity(playerPed)
    eachOwnPed(function(npcId, ped)
        if not pending[ped] and due(ped, now) and not excluded(ped, npcId, now)
            and IsEntityTouchingEntity(playerPed, ped)
            and towards(velocity, origin, GetEntityCoords(ped)) then
            pending[ped] = { since = now, npc_id = npcId, ragdolled = IsPedRagdoll(ped) }
        end
    end)
    return reported
end

CreateThread(function()
    while true do
        Wait(config().TickMs)
        HumalikeNpcShove.Tick(GetGameTimer())
    end
end)
