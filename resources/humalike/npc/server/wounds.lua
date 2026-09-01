
-- Clients report raw hits; classification and authority checks stay server-side.
local wounds = {} -- npcId -> array of { region, kind, severity }

local function ambientLease(entityId)
    if HumalikeResolveAmbientLease then return HumalikeResolveAmbientLease(entityId) end
    local lease = AmbientNpcLeases and AmbientNpcLeases[entityId] or nil
    return lease, lease and entityId or nil
end

local SEVERITY_RANK = { minor = 1, serious = 2, critical = 3 }

local function config()
    return Config.Wounds or {}
end

local function enabled()
    return config().Enabled ~= false
end
function HumalikeWoundsOf(npcId)
    local held = wounds[npcId]
    if not held then return {} end
    local out = {}
    for index, wound in ipairs(held) do
        out[index] = { region = wound.region, kind = wound.kind, severity = wound.severity }
    end
    return out
end
function HumalikeClearWounds(npcId)
    wounds[npcId] = nil
    TriggerClientEvent('humalike:npc:npcWounds', -1, npcId, {})
end
local function trim(held)
    local cap = math.max(0, math.floor(tonumber(config().MaxWounds) or 6))
    while #held > cap do
        local weakest, weakestRank = 1, math.huge
        for index, wound in ipairs(held) do
            local rank = SEVERITY_RANK[wound.severity] or 0
            if rank < weakestRank then weakest, weakestRank = index, rank end
        end
        table.remove(held, weakest)
    end
end
local function record(npcId, wound)
    local held = wounds[npcId] or {}
    for _, existing in ipairs(held) do
        if existing.region == wound.region and existing.kind == wound.kind then
            if (SEVERITY_RANK[wound.severity] or 0) > (SEVERITY_RANK[existing.severity] or 0) then
                existing.severity = wound.severity
                wounds[npcId] = held
                return true
            end
            return false
        end
    end
    table.insert(held, 1, wound)
    trim(held)
    wounds[npcId] = held
    return true
end
local function refuse(reason, ...)
    HumalikeDebug('wounds: refused (' .. reason .. ')', ...)
end

RegisterNetEvent('humalike:npc:npcDamaged')
AddEventHandler('humalike:npc:npcDamaged', function(npcId, entityId, boneId, weaponHash, damage)
    if not enabled() then return refuse('disabled') end
    local playerId = tonumber(source)
    HumalikeDebug(('wounds: report npc=%s entity=%s bone=%s weapon=%s damage=%s'):format(
        tostring(npcId), tostring(entityId), tostring(boneId), tostring(weaponHash),
        tostring(damage)))
    if not playerId or playerId <= 0 or playerId % 1 ~= 0
        or type(npcId) ~= 'string'
        or type(entityId) ~= 'number' or entityId <= 0 or entityId % 1 ~= 0
        or type(boneId) ~= 'number' or type(weaponHash) ~= 'number'
        or type(damage) ~= 'number' or damage ~= damage then
        return refuse('malformed')
    end
    if not HumalikePlayer.IsCharacterLoaded(playerId) then
        return refuse('character not loaded')
    end
    if damage > 0 and damage < (tonumber(config().MinDamage) or 5) then
        return refuse(('damage %s below floor'):format(tostring(damage)))
    end

    local lease, entity = ambientLease(entityId)
    if not lease then return refuse('no lease for entity ' .. tostring(entityId)) end
    if lease.npc_id ~= npcId then return refuse('lease is for ' .. tostring(lease.npc_id)) end
    if type(lease.lease_token) ~= 'string' then return refuse('lease has no token') end
    if not entity then return refuse('entity gone') end
    if GetEntityRoutingBucket(entity) ~= GetPlayerRoutingBucket(playerId) then
        return refuse('routing bucket mismatch')
    end
    -- The damage bone is trustworthy only from the current entity owner.
    local owner = NetworkGetEntityOwner and NetworkGetEntityOwner(entity) or -1
    if owner ~= nil and owner >= 0 and owner ~= playerId then
        return refuse(('reported by %s, owned by %s'):format(tostring(playerId), tostring(owner)))
    end

    local wound = HumalikeClassifyWound(boneId, weaponHash, damage)
    if not record(npcId, wound) then return end

    HumalikeDebug(('wounds: %s took a %s %s to the %s'):format(
        npcId, wound.severity, wound.kind, wound.region))
    -- Send the full set so dropped deltas cannot desynchronize clients.
    TriggerClientEvent('humalike:npc:npcWounds', -1, npcId, HumalikeWoundsOf(npcId))
    if HumalikeReportNpcWounds then
        HumalikeReportNpcWounds(playerId, npcId, entityId, lease.lease_token, HumalikeWoundsOf(npcId))
    end
end)
RegisterNetEvent('humalike:npc:requestWounds')
AddEventHandler('humalike:npc:requestWounds', function()
    local playerId = tonumber(source)
    if not playerId or playerId <= 0 then return end
    for npcId in pairs(wounds) do
        TriggerClientEvent('humalike:npc:npcWounds', playerId, npcId, HumalikeWoundsOf(npcId))
    end
end)
exports('GetNpcWounds', function(npcId)
    return HumalikeWoundsOf(npcId)
end)
