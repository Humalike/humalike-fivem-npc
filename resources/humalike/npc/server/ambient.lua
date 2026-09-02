local discoveryRadius = Config.AmbientBootstrapRadius
local activeLeases = {}
local controls = {}
local lastControlRequestBySource = {}
local reviveSessions = {}
local lastReviveRequestBySource = {}
local lastLeaseSnapshotRequestBySource = {}
local lastLeaseDigestBySource = {}
local latestLeaseSnapshot = {
    enabled = false,
    discovery_radius = Config.AmbientBootstrapRadius,
    lease_ttl_seconds = 0,
    leases = {},
}
local voiceMuteRevision = -1

local function ambientKey(entityId)
    return tostring(entityId)
end
local function resolveAmbientEntity(entityId)
    if type(entityId) ~= 'number' or entityId % 1 ~= 0 or entityId <= 0 then return nil end
    if NetworkDoesEntityExistWithNetworkId
        and not NetworkDoesEntityExistWithNetworkId(entityId) then return nil end
    -- Leases store network IDs; resolve a current handle only at native calls.
    local entity = NetworkGetEntityFromNetworkId(entityId)
    if not entity or entity <= 0 or not DoesEntityExist(entity) then return nil end
    return entity
end

function HumalikeResolveAmbientEntity(entityId)
    return resolveAmbientEntity(entityId)
end

function HumalikeResolveAmbientLease(entityId)
    local lease = activeLeases[ambientKey(entityId)]
    if not lease then return nil, nil end
    return lease, resolveAmbientEntity(entityId)
end

local function broadcastControl(key, control, routingBucket)
    local public = control and {
        mode = control.mode,
        controller_source = control.controller_source,
        entity_id = control.entity_id,
        routing_bucket = control.routing_bucket,
        npc_id = control.npc_id,
    } or nil
    local bucket = routingBucket or (control and control.routing_bucket)
    if bucket == nil then return end
    for _, playerId in ipairs(GetPlayers()) do
        if GetPlayerRoutingBucket(playerId) == bucket then
            TriggerClientEvent('humalike:npc:ambientControlChanged', playerId, key, public)
        end
    end
end

local function controlSnapshot(routingBucket)
    local snapshot = {}
    for key, control in pairs(controls) do
        if control.routing_bucket == routingBucket then
            snapshot[key] = {
                mode = control.mode,
                controller_source = control.controller_source,
                entity_id = control.entity_id,
                routing_bucket = control.routing_bucket,
                npc_id = control.npc_id,
            }
        end
    end
    return snapshot
end

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function distanceSquared(left, right)
    local dx = left.x - right.x
    local dy = left.y - right.y
    local dz = left.z - right.z
    return dx * dx + dy * dy + dz * dz
end
local function playerLeaseSlice(playerId, body)
    local leases = {}
    if not body.enabled or type(body.leases) ~= 'table' then return leases end
    local bucket = GetPlayerRoutingBucket(playerId)
    local playerPed = GetPlayerPed(playerId)
    if not playerPed or playerPed <= 0 or not DoesEntityExist(playerPed) then return leases end
    local playerCoords = GetEntityCoords(playerPed)
    local scope = Config.AmbientLeaseScopeDistance

    for _, lease in ipairs(body.leases) do
        local entityId = lease.entity_id
        local entity = resolveAmbientEntity(entityId)
        if lease.routing_bucket == bucket and entity
            and GetEntityType(entity) == 1 and not IsPedAPlayer(entity)
            and GetEntityRoutingBucket(entity) == bucket
            and distanceSquared(playerCoords, GetEntityCoords(entity)) <= scope * scope then
            leases[#leases + 1] = {
                entity_id = entityId,
                network_id = entityId,
                routing_bucket = lease.routing_bucket,
                npc_id = lease.npc_id,
                lease_token = lease.lease_token,
                display_name = lease.display_name,
                language = lease.language,
                expires_in_seconds = lease.expires_in_seconds,
                voice_active = lease.voice_active,
                voice_muted = lease.voice_muted == true,
            }
        end
    end
    return leases
end
local function leaseDigest(body, leases)
    local parts = {}
    for index, lease in ipairs(leases) do
        parts[index] = ('%s|%s|%d|%d|%s|%s|%s'):format(
            lease.npc_id, lease.lease_token, lease.entity_id, lease.network_id,
            tostring(lease.display_name), tostring(lease.language),
            tostring(lease.voice_muted))
    end
    table.sort(parts)
    return ('%s;%s;%s;%s'):format(tostring(body.enabled == true),
        tostring(body.discovery_radius), tostring(body.lease_ttl_seconds),
        table.concat(parts, ';'))
end
local function sendAmbientLeases(playerId, body, force)
    local leases = playerLeaseSlice(playerId, body)
    local digest = leaseDigest(body, leases)
    if not force and lastLeaseDigestBySource[playerId] == digest then return false end
    lastLeaseDigestBySource[playerId] = digest
    TriggerClientEvent('humalike:npc:ambientLeases', playerId, {
        enabled = body.enabled == true,
        discovery_radius = body.discovery_radius,
        lease_ttl_seconds = body.lease_ttl_seconds,
        leases = leases,
    })
    return true
end

local function broadcastAmbientLeases(body)
    for _, playerId in ipairs(GetPlayers()) do sendAmbientLeases(playerId, body) end
end

local function releaseControl(key, reason)
    local control = controls[key]
    if not control then return end
    controls[key] = nil
    HumalikeDebug('ambient control released for %s (%s)', key, reason or 'unknown')
    broadcastControl(key, nil, control.routing_bucket)
end

local MOVEMENT_RELEASE_ACTIONS = {
    follow_player = true,
    stop_following = true,
    release_movement = true,
    enter_vehicle = true,
    walk_away = true,
}
function HumalikeApplyAmbientMovementAction(target, lease, entity, actionKey, params)
    local key = ambientKey(target.entity_id)
    if actionKey == 'hold_position' then
        local playerId = params and params.player_id
        if type(playerId) ~= 'number' or playerId % 1 ~= 0 or playerId < 1
            or not GetPlayerName(playerId) then return false, 'invalid_action_player' end
        if GetPlayerRoutingBucket(playerId) ~= lease.routing_bucket then
            return false, 'action_player_wrong_bucket'
        end
        controls[key] = {
            mode = 'held',
            controller_source = playerId,
            entity_id = target.entity_id,
            routing_bucket = lease.routing_bucket,
            npc_id = lease.npc_id,
            lease_token = lease.lease_token,
            entity_handle = entity,
        }
        Entity(entity).state:set('humalike_action', nil, true)
        broadcastControl(key, controls[key])
        HumalikeDebug('ambient ped %s held by voice action from source %s', key, playerId)
        return true
    end

    if MOVEMENT_RELEASE_ACTIONS[actionKey] then
        releaseControl(key, ('voice action %s'):format(actionKey))
        if actionKey == 'release_movement' then
            Entity(entity).state:set('humalike_action', nil, true)
            return true
        end
    end
    return nil
end

local function applyLeaseSnapshot(body)
    local nextLeases = {}
    local publicLeases = {}
    if body.enabled and type(body.leases) == 'table' then
        for _, lease in ipairs(body.leases) do
            if type(lease.entity_id) == 'number' and type(lease.routing_bucket) == 'number'
                and type(lease.npc_id) == 'string' and type(lease.lease_token) == 'string' then
                local entity = resolveAmbientEntity(lease.entity_id)
                if entity and GetEntityType(entity) == 1
                    and not IsPedAPlayer(entity)
                    and GetEntityRoutingBucket(entity) == lease.routing_bucket then
                    nextLeases[ambientKey(lease.entity_id)] = lease
                    publicLeases[entity] = {
                        npc_id = lease.npc_id,
                        lease_token = lease.lease_token,
                        entity_id = lease.entity_id,
                        network_id = lease.entity_id,
                    }
                    local owner = NetworkGetEntityOwner(entity)
                    Entity(entity).state:set('humalike_position_reporter', owner, true)
                end
            end
        end
    end

    local staleControls = {}
    for key, control in pairs(controls) do
        local lease = nextLeases[key]
        if not lease or lease.lease_token ~= control.lease_token
            or lease.npc_id ~= control.npc_id then
            staleControls[#staleControls + 1] = key
        end
    end
    for _, key in ipairs(staleControls) do releaseControl(key, 'lease ended') end
    for key in pairs(activeLeases) do
        if not nextLeases[key] then
            local entity = resolveAmbientEntity(tonumber(key))
            if entity and DoesEntityExist(entity) then
                Entity(entity).state:set('humalike_position_reporter', nil, true)
            end
        end
    end
    local freshLeases = {}
    for key, lease in pairs(nextLeases) do
        local previous = activeLeases[key]
        if not previous or previous.npc_id ~= lease.npc_id
            or previous.lease_token ~= lease.lease_token then
            freshLeases[#freshLeases + 1] = lease
        end
    end
    if HumalikeClearWounds then
        local stillLeased = {}
        for _, lease in pairs(nextLeases) do
            stillLeased[lease.npc_id] = lease.lease_token
        end
        for key, lease in pairs(activeLeases) do
            local token = stillLeased[lease.npc_id]
            local sameBody = nextLeases[key] ~= nil and token == lease.lease_token
            if not sameBody then HumalikeClearWounds(lease.npc_id) end
        end
    end
    activeLeases = nextLeases
    AmbientNpcLeases = publicLeases
    return freshLeases
end

AmbientNpcLeases = {} -- network id -> lease
function HumalikeFindAmbientLease(npcId)
    if type(npcId) ~= 'string' then return nil end
    for _, lease in pairs(activeLeases) do
        if lease.npc_id == npcId then
            local entity = resolveAmbientEntity(lease.entity_id)
            return {
                npc_id = lease.npc_id,
                entity_id = lease.entity_id,
                network_id = lease.entity_id,
                entity_handle = entity,
                routing_bucket = lease.routing_bucket,
                lease_token = lease.lease_token,
            }
        end
    end
    return nil
end

function ValidateAmbientActionTarget(target)
    if type(target) ~= 'table' or type(target.entity_id) ~= 'number'
        or target.entity_id % 1 ~= 0 or target.entity_id <= 0
        or type(target.npc_id) ~= 'string' or target.npc_id == ''
        or type(target.lease_token) ~= 'string' or target.lease_token == ''
        or type(target.routing_bucket) ~= 'number'
        or target.routing_bucket % 1 ~= 0 then return nil, nil, 'invalid_ambient_target' end

    local lease = activeLeases[ambientKey(target.entity_id)]
    if not lease or lease.npc_id ~= target.npc_id
        or lease.lease_token ~= target.lease_token
        or lease.routing_bucket ~= target.routing_bucket then
        return nil, nil, 'ambient_lease_expired'
    end

    local entity = resolveAmbientEntity(target.entity_id)
    if not entity or GetEntityType(entity) ~= 1
        or IsPedAPlayer(entity) or GetEntityHealth(entity) <= 0
        or GetEntityRoutingBucket(entity) ~= target.routing_bucket then
        return nil, nil, 'ambient_entity_unavailable'
    end
    return lease, entity
end

function SendAmbientActionToOwner(target, entity, actionKey, params)
    local owner = NetworkGetEntityOwner(entity)
    if not owner or owner < 1 or not GetPlayerName(owner)
        or GetPlayerRoutingBucket(owner) ~= target.routing_bucket then return false end
    TriggerClientEvent('humalike:npc:playAmbientAction', owner, target.npc_id,
        target.entity_id, target.lease_token, actionKey, params or {})
    return true
end

local function observedAt()
    local nowMs = os.time() * 1000 + (GetGameTimer() % 1000)
    local seconds = math.floor(nowMs / 1000)
    return os.date('!%Y-%m-%dT%H:%M:%S', seconds)
        .. string.format('.%03dZ', nowMs % 1000)
end

local function validZoneCode(value)
    return value == nil or (type(value) == 'string' and #value >= 1 and #value <= 32
        and value:match('^[A-Z0-9_]+$') ~= nil)
end

local function validCoordinate(value)
    return type(value) == 'number' and value == value and math.abs(value) <= 10000
end

local function validateCandidate(playerCoords, playerBucket, candidate)
    if type(candidate) ~= 'table' or type(candidate.network_id) ~= 'number'
        or candidate.network_id % 1 ~= 0 or candidate.network_id <= 0
        or not validCoordinate(candidate.x) or not validCoordinate(candidate.y)
        or not validCoordinate(candidate.z)
        or type(candidate.model_hash) ~= 'number' or candidate.model_hash % 1 ~= 0
        or not validZoneCode(candidate.zone_code) then return nil end

    if NetworkDoesEntityExistWithNetworkId
        and not NetworkDoesEntityExistWithNetworkId(candidate.network_id) then return nil end
    local entity = NetworkGetEntityFromNetworkId(candidate.network_id)
    if not entity or entity <= 0 or not DoesEntityExist(entity)
        or GetEntityType(entity) ~= 1 or IsPedAPlayer(entity)
        or GetEntityHealth(entity) <= 0 or GetVehiclePedIsIn(entity, false) ~= 0
        or GetEntityRoutingBucket(entity) ~= playerBucket then return nil end

    local entityCoords = GetEntityCoords(entity)
    if distanceSquared(playerCoords, entityCoords) > discoveryRadius * discoveryRadius then return nil end

    local reportedCoords = vector3(candidate.x, candidate.y, candidate.z)
    local tolerance = Config.AmbientCoordinateTolerance
    if distanceSquared(reportedCoords, entityCoords) > tolerance * tolerance then return nil end
    local modelHash = unsignedHash(GetEntityModel(entity))
    if modelHash ~= candidate.model_hash then return nil end

    return {
        entity_id = candidate.network_id,
        model_hash = modelHash,
        x = entityCoords.x,
        y = entityCoords.y,
        z = entityCoords.z,
        heading = GetEntityHeading(entity),
        zone_code = candidate.zone_code,
        routing_bucket = playerBucket,
        observed_at = observedAt(),
    }
end

function HumalikeValidateAmbientCandidates(body)
    local playerId = tonumber(body.reporter_session_id)
    if not playerId or not HumalikePlayer.IsCharacterLoaded(playerId) then
        return { validated = {}, rejected_network_ids = {} }
    end
    local ped = GetPlayerPed(playerId)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then
        return { validated = {}, rejected_network_ids = {} }
    end
    local validated, rejected, seen = {}, {}, {}
    for index, candidate in ipairs(body.candidates or {}) do
        if index > Config.AmbientMaxCandidatesPerReport then break end
        local observation = validateCandidate(GetEntityCoords(ped),
            GetPlayerRoutingBucket(playerId), candidate)
        if observation and not seen[observation.entity_id] then
            seen[observation.entity_id] = true
            validated[#validated + 1] = observation
        else
            rejected[#rejected + 1] = candidate.network_id
        end
    end
    return { request_id = body.request_id, validated = validated,
        rejected_network_ids = rejected }
end

local leaseRevision = -1
function HumalikeApplyAmbientLeaseSnapshot(body)
    local nextRevision = tonumber(body.revision)
    if not nextRevision or nextRevision <= leaseRevision then return false end
    leaseRevision = nextRevision
    body.discovery_radius = body.discovery_radius or discoveryRadius
    body.lease_ttl_seconds = body.lease_ttl_seconds or 15
    local freshLeases = applyLeaseSnapshot(body)
    latestLeaseSnapshot = body
    broadcastAmbientLeases(body)
    for _, lease in ipairs(freshLeases) do
        local pose = NpcPoses[lease.npc_id]
        if pose then
            local target = {
                npc_id = lease.npc_id,
                entity_id = lease.entity_id,
                lease_token = lease.lease_token,
                routing_bucket = lease.routing_bucket,
            }
            ReplayNpcPoseWhenReady(lease.npc_id, pose, function()
                local current = activeLeases[ambientKey(lease.entity_id)]
                return current ~= nil and current.lease_token == lease.lease_token
                    and resolveAmbientEntity(lease.entity_id) ~= nil
            end, function()
                local entity = resolveAmbientEntity(lease.entity_id)
                local sent = entity and SendAmbientActionToOwner(target, entity, pose, {}) or false
                if sent and RefreshNpcPoseTarget then
                    RefreshNpcPoseTarget(lease.npc_id, target)
                end
                return sent
            end)
        end
    end
    return true
end

function HumalikeApplyVoiceMuteSnapshot(body)
    local revision = tonumber(body.revision)
    if not revision or revision <= voiceMuteRevision or type(body.npcs) ~= 'table'
        or #body.npcs > 1024 then return false end

    local states = {}
    for _, item in ipairs(body.npcs) do
        if type(item) ~= 'table' or type(item.npc_id) ~= 'string'
            or item.npc_id == '' or type(item.voice_muted) ~= 'boolean'
            or states[item.npc_id] ~= nil then return false end
        states[item.npc_id] = item.voice_muted
    end

    voiceMuteRevision = revision
    for npcId, entry in pairs(NpcRegistry or {}) do
        local muted = states[npcId] == true
        entry.voice_muted = muted
    end
    for _, lease in pairs(activeLeases) do
        lease.voice_muted = states[lease.npc_id] == true
    end
    for _, lease in ipairs(latestLeaseSnapshot.leases or {}) do
        lease.voice_muted = states[lease.npc_id] == true
    end
    TriggerClientEvent('humalike:npc:voiceMuteSnapshot', -1, revision, states)
    return true
end

function HumalikeClearAmbientLeases()
    leaseRevision = leaseRevision + 1
    local body = {
        revision = leaseRevision,
        enabled = false,
        discovery_radius = discoveryRadius,
        lease_ttl_seconds = 15,
        leases = {},
    }
    applyLeaseSnapshot(body)
    latestLeaseSnapshot = body
    broadcastAmbientLeases(body)
end
function HumalikeValidateAmbientLeases(body)
    local valid, invalid, invalidLeases = {}, {}, {}
    for _, requested in ipairs(body.leases or {}) do
        local entityId = tonumber(requested.entity_id)
        local entity = entityId and resolveAmbientEntity(entityId) or nil
        local expectedModel = tonumber(requested.model_hash)
        local expectedBucket = tonumber(requested.routing_bucket)
        local reason
        if not entityId or entityId <= 0 or not expectedModel or not expectedBucket then
            reason = 'bad_id'
        elseif not entity then
            reason = 'missing'
        elseif GetEntityType(entity) ~= 1 then reason = 'type'
        elseif IsPedAPlayer(entity) then reason = 'player'
        elseif GetVehiclePedIsIn(entity, false) ~= 0 then
            -- A leased ped may enter a vehicle; an unleased candidate may not start there.
            local active = activeLeases[ambientKey(entityId)]
            if not active or active.entity_id ~= entityId
                or active.lease_token ~= requested.lease_token
                or active.routing_bucket ~= expectedBucket then reason = 'vehicle' end
        end
        if not reason and GetEntityRoutingBucket(entity) ~= expectedBucket then reason = 'bucket' end
        if not reason and unsignedHash(GetEntityModel(entity)) ~= expectedModel then reason = 'model' end

        if not reason then
            valid[#valid + 1] = {
                entity_id = entityId,
                model_hash = expectedModel,
                routing_bucket = expectedBucket,
                lease_token = requested.lease_token,
            }
        else
            invalid[#invalid + 1] = entityId or 0
            invalidLeases[#invalidLeases + 1] = {
                entity_id = entityId or 0,
                reason = reason,
            }
        end
    end
    return { valid = valid, invalid_entity_ids = invalid, invalid_leases = invalidLeases }
end

local function validateControlRequest(source, entityId, npcId, leaseToken)
    if type(entityId) ~= 'number' or entityId % 1 ~= 0 or entityId <= 0
        or type(npcId) ~= 'string' or type(leaseToken) ~= 'string' then return nil end
    if not HumalikePlayer.IsCharacterLoaded(source) then return nil end

    local playerPed = GetPlayerPed(source)
    if not playerPed or playerPed <= 0 or not DoesEntityExist(playerPed) then return nil end
    local bucket = GetPlayerRoutingBucket(source)
    local key = ambientKey(entityId)
    local lease = activeLeases[key]
    if not lease or lease.routing_bucket ~= bucket or lease.npc_id ~= npcId
        or lease.lease_token ~= leaseToken then return nil end

    local entity = resolveAmbientEntity(entityId)
    if not entity
        or GetEntityType(entity) ~= 1 or IsPedAPlayer(entity) or GetEntityHealth(entity) <= 0
        or GetEntityRoutingBucket(entity) ~= bucket then return nil end
    local maxDistance = Config.AmbientControl.ServerValidationDistance
        or Config.AmbientControl.InteractionDistance
    if distanceSquared(GetEntityCoords(playerPed), GetEntityCoords(entity))
        > maxDistance * maxDistance then return nil end
    return key, lease, entity
end

local function validateReviveTarget(source, entityId, npcId, leaseToken)
    if type(entityId) ~= 'number' or entityId % 1 ~= 0 or entityId <= 0
        or type(npcId) ~= 'string' or type(leaseToken) ~= 'string' then return nil end
    if not HumalikePlayer.IsCharacterLoaded(source) then return nil end

    local playerPed = GetPlayerPed(source)
    if not playerPed or playerPed <= 0 or not DoesEntityExist(playerPed)
        or GetEntityHealth(playerPed) <= 0 then return nil end
    local bucket = GetPlayerRoutingBucket(source)
    local key = ambientKey(entityId)
    local lease = activeLeases[key]
    if not lease or lease.routing_bucket ~= bucket or lease.npc_id ~= npcId
        or lease.lease_token ~= leaseToken then return nil end

    local entity = resolveAmbientEntity(entityId)
    if not entity
        or GetEntityType(entity) ~= 1 or IsPedAPlayer(entity)
        or GetEntityRoutingBucket(entity) ~= bucket or GetEntityHealth(entity) > 0 then return nil end
    local maxDistance = Config.AmbientRevive.InteractionDistance
    if distanceSquared(GetEntityCoords(playerPed), GetEntityCoords(entity))
        > maxDistance * maxDistance then return nil end
    return key, lease, entity
end

RegisterNetEvent('humalike:npc:setAmbientControl')
AddEventHandler('humalike:npc:setAmbientControl', function(entityId, npcId, leaseToken, requestedMode)
    local source = source
    local now = GetGameTimer()
    if now - (lastControlRequestBySource[source] or -Config.AmbientControl.RequestCooldownMs)
        < Config.AmbientControl.RequestCooldownMs then return end
    lastControlRequestBySource[source] = now

    if requestedMode ~= 'held' and requestedMode ~= 'released' then return end
    local key, lease, entity = validateControlRequest(source, entityId, npcId, leaseToken)
    if not key then return end

    local current = controls[key]
    if requestedMode == 'held' then
        if current then return end
        current = {
            mode = 'held',
            controller_source = source,
            entity_id = entityId,
            routing_bucket = lease.routing_bucket,
            npc_id = lease.npc_id,
            lease_token = lease.lease_token,
            entity_handle = entity,
        }
        controls[key] = current
        HumalikeDebug('ambient ped %s held by source %s', key, source)
        broadcastControl(key, current)
    elseif current and current.controller_source == source then
        releaseControl(key, 'manual')
    end
end)

RegisterNetEvent('humalike:npc:requestAmbientControls')
AddEventHandler('humalike:npc:requestAmbientControls', function()
    local requestingSource = source
    if not HumalikePlayer.IsCharacterLoaded(requestingSource) then return end
    TriggerClientEvent('humalike:npc:ambientControlSnapshot', requestingSource,
        controlSnapshot(GetPlayerRoutingBucket(requestingSource)))
end)

RegisterNetEvent('humalike:npc:beginAmbientRevive')
AddEventHandler('humalike:npc:beginAmbientRevive', function(entityId, npcId, leaseToken)
    local source = source
    local now = GetGameTimer()
    if now - (lastReviveRequestBySource[source] or -Config.AmbientControl.RequestCooldownMs)
        < Config.AmbientControl.RequestCooldownMs then return end
    lastReviveRequestBySource[source] = now
    local key, lease, entity = validateReviveTarget(source, entityId, npcId, leaseToken)
    if not key or reviveSessions[key] then return end
    reviveSessions[key] = {
        source = source,
        started_at = GetGameTimer(),
        entity_id = entityId,
        npc_id = lease.npc_id,
        lease_token = lease.lease_token,
        routing_bucket = lease.routing_bucket,
        entity_handle = entity,
    }
    TriggerClientEvent('humalike:npc:ambientReviveStarted', source, {
        key = key,
        entity_id = entityId,
        network_id = entityId,
        duration_ms = Config.AmbientRevive.DurationMs,
    })
end)

RegisterNetEvent('humalike:npc:cancelAmbientRevive')
AddEventHandler('humalike:npc:cancelAmbientRevive', function(key)
    local session = type(key) == 'string' and reviveSessions[key] or nil
    if session and session.source == source then reviveSessions[key] = nil end
end)

RegisterNetEvent('humalike:npc:completeAmbientRevive')
AddEventHandler('humalike:npc:completeAmbientRevive', function(key)
    local source = source
    local session = type(key) == 'string' and reviveSessions[key] or nil
    if not session or session.source ~= source then return end
    local elapsed = GetGameTimer() - session.started_at
    if elapsed < Config.AmbientRevive.DurationMs - Config.AmbientRevive.CompletionToleranceMs then
        reviveSessions[key] = nil
        return
    end

    local validKey, _, entity = validateReviveTarget(source, session.entity_id,
        session.npc_id, session.lease_token)
    if validKey ~= key then
        reviveSessions[key] = nil
        return
    end
    reviveSessions[key] = nil
    for _, playerId in ipairs(GetPlayers()) do
        if GetPlayerRoutingBucket(playerId) == session.routing_bucket then
            TriggerClientEvent('humalike:npc:reviveAmbientPed', playerId,
                session.entity_id, session.entity_id, session.npc_id,
                session.lease_token)
        end
    end
    TriggerEvent('humalike:npc:npcRevived', source, session.npc_id, session.entity_id,
        session.lease_token)
end)

CreateThread(function()
    while true do
        Wait(1000)
        local stale = {}
        local staleRevives = {}
        local releaseDistance = Config.AmbientControl.ReleaseDistance
        for key, control in pairs(controls) do
            local playerPed = GetPlayerPed(control.controller_source)
            local entity = resolveAmbientEntity(control.entity_id)
            if not playerPed or playerPed <= 0 or not DoesEntityExist(playerPed)
                or not entity
                or GetEntityHealth(entity) <= 0
                or GetPlayerRoutingBucket(control.controller_source) ~= control.routing_bucket
                or GetEntityRoutingBucket(entity) ~= control.routing_bucket
                or distanceSquared(GetEntityCoords(playerPed), GetEntityCoords(entity))
                    > releaseDistance * releaseDistance then
                stale[#stale + 1] = key
            else
                control.entity_handle = entity
            end
        end
        for _, key in ipairs(stale) do releaseControl(key, 'controller unavailable or too far') end
        local now = GetGameTimer()
        for key, session in pairs(reviveSessions) do
            local validKey, _, entity = validateReviveTarget(session.source, session.entity_id,
                session.npc_id, session.lease_token)
            if now - session.started_at > Config.AmbientRevive.SessionTimeoutMs
                or not activeLeases[key]
                or activeLeases[key].lease_token ~= session.lease_token
                or validKey ~= key then
                staleRevives[#staleRevives + 1] = key
            elseif entity then
                session.entity_handle = entity
            end
        end
        for _, key in ipairs(staleRevives) do reviveSessions[key] = nil end
    end
end)
CreateThread(function()
    while true do
        Wait(Config.AmbientLeaseScopeTickMs)
        for _, playerId in ipairs(GetPlayers()) do
            sendAmbientLeases(tonumber(playerId) or playerId, latestLeaseSnapshot)
        end
    end
end)
CreateThread(function()
    while true do
        Wait(2000)
        for key in pairs(activeLeases) do
            local entity = resolveAmbientEntity(tonumber(key))
            if entity then
                local owner = NetworkGetEntityOwner(entity)
                local state = Entity(entity).state
                if state.humalike_position_reporter ~= owner then
                    state:set('humalike_position_reporter', owner, true)
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local droppedSource = source
    lastControlRequestBySource[droppedSource] = nil
    lastReviveRequestBySource[droppedSource] = nil
    lastLeaseSnapshotRequestBySource[droppedSource] = nil
    lastLeaseDigestBySource[droppedSource] = nil
    local stale = {}
    local staleRevives = {}
    for key, control in pairs(controls) do
        if control.controller_source == droppedSource then stale[#stale + 1] = key end
    end
    for _, key in ipairs(stale) do releaseControl(key, 'player dropped') end
    for key, session in pairs(reviveSessions) do
        if session.source == droppedSource then staleRevives[#staleRevives + 1] = key end
    end
    for _, key in ipairs(staleRevives) do reviveSessions[key] = nil end
end)

RegisterNetEvent('humalike:npc:requestAmbientLeaseSnapshot')
AddEventHandler('humalike:npc:requestAmbientLeaseSnapshot', function()
    local playerId = source
    local now = GetGameTimer()
    if now - (lastLeaseSnapshotRequestBySource[playerId] or -1000) < 1000 then return end
    lastLeaseSnapshotRequestBySource[playerId] = now
    if GetPlayerName(playerId) then
        sendAmbientLeases(playerId, latestLeaseSnapshot, true)
    end
end)

AddEventHandler('onPlayerBucketChange', function(playerId)
    -- Routing natives are unsafe inside the OneSync callback.
    SetTimeout(0, function()
        local target = tonumber(playerId)
        if target and GetPlayerName(target) then
            sendAmbientLeases(target, latestLeaseSnapshot, true)
        end
    end)
end)
