HumalikeNpcPopulation = HumalikeNpcPopulation or {}
local bodies = {}
local planRevision = -1
local spawnPointRequests = {}
local failedBodies = {}
local reportDirty = false
local reportInFlight = false
local reportStartedAt = 0
local reportGeneration = 0
local reportFailures = 0
local reportRetryAt = 0
local lastReportAt = nil
local lastContactAt = nil
local requestSequence = 0
local enabled = false
local copsAllowed = false
local edgeLost = false
local broadcast = { enabled = false, cops_allowed = false }

local function config()
    return Config.Population
end

local function copsConvar()
    return GetConvar('humalike_population_cops', 'false') == 'true'
end

local function statePayload()
    return { enabled = enabled and not edgeLost, cops_allowed = copsAllowed }
end

local function publishState()
    local payload = statePayload()
    if payload.enabled == broadcast.enabled and payload.cops_allowed == broadcast.cops_allowed then
        return false
    end
    broadcast = payload
    TriggerClientEvent('humalike:npc:populationState', -1, payload)
    return true
end

local function backoff(failures)
    local cfg = config()
    return math.min(cfg.RetryBackoffMs * (2 ^ math.min(failures, 10)), cfg.RetryBackoffCapMs)
end

local function contact(now)
    lastContactAt = now
    if edgeLost then
        edgeLost = false
        publishState()
    end
end

local function validPoint(point)
    return type(point) == 'table' and HumalikeValidCoordinate(point.x)
        and HumalikeValidCoordinate(point.y) and HumalikeValidCoordinate(point.z)
        and (point.heading == nil or HumalikeValidCoordinate(point.heading))
end

local function validBehaviour(body)
    if body.behaviour ~= nil and body.behaviour ~= 'wander' and body.behaviour ~= 'stand'
        and body.behaviour ~= 'scenario' then return false end
    if body.scenario ~= nil and (type(body.scenario) ~= 'string' or #body.scenario > 48
        or not body.scenario:match('^[A-Z0-9_]+$')) then return false end
    if body.walk_rate ~= nil and (type(body.walk_rate) ~= 'number' or body.walk_rate ~= body.walk_rate
        or body.walk_rate < 0.5 or body.walk_rate > 1.0) then return false end
    return true
end

local function validBody(body)
    if type(body) ~= 'table' or not validBehaviour(body)
        or type(body.body_id) ~= 'string' or body.body_id == ''
        or #body.body_id > 64 or type(body.model) ~= 'string' or body.model == ''
        or (body.kind ~= nil and body.kind ~= 'persona' and body.kind ~= 'extra')
        or type(body.model_hash) ~= 'number' or type(body.routing_bucket) ~= 'number'
        or body.routing_bucket % 1 ~= 0 or body.routing_bucket < 0
        or (body.zone_code ~= nil and type(body.zone_code) ~= 'string')
        or (body.style_seed ~= nil and type(body.style_seed) ~= 'number')
        or (body.anchor_session_id ~= nil and type(body.anchor_session_id) ~= 'number')
        or type(body.candidates) ~= 'table' or #body.candidates == 0 then return false end
    if body.model_hash ~= HumalikeUnsignedHash(GetHashKey(body.model)) then return false end
    if body.kind ~= 'extra' and (type(body.npc_id) ~= 'string' or body.npc_id == '') then
        return false
    end
    for _, point in ipairs(body.candidates) do
        if not validPoint(point) then return false end
    end
    return true
end

local function playerPed(playerId, bucket)
    if type(playerId) ~= 'number' or not GetPlayerName(playerId)
        or GetPlayerRoutingBucket(playerId) ~= bucket then return nil end
    local ped = GetPlayerPed(playerId)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

local function spawnPointClient(record)
    local origin = record.candidates[1]
    local best, bestDistance = nil, config().SpawnPointClientRange ^ 2
    local anchor = playerPed(record.anchor_session_id, record.routing_bucket)
    if anchor and HumalikeDistanceSquared(GetEntityCoords(anchor), origin) <= bestDistance then
        return record.anchor_session_id
    end
    for _, playerId in ipairs(GetPlayers()) do
        local id = tonumber(playerId)
        local ped = playerPed(id, record.routing_bucket)
        if ped then
            local distance = HumalikeDistanceSquared(GetEntityCoords(ped), origin)
            if distance <= bestDistance then best, bestDistance = id, distance end
        end
    end
    return best
end

-- Only a nearby client sees the navmesh; nil fails the spawn.
local function resolveSpawnPoint(record)
    local playerId = spawnPointClient(record)
    if not playerId then return nil end
    requestSequence = requestSequence + 1
    local requestId = ('%s:%d'):format(record.body_id, requestSequence)
    local request = { player_id = playerId, candidates = record.candidates }
    spawnPointRequests[requestId] = request
    TriggerClientEvent('humalike:npc:populationSpawnPoint', playerId, requestId, record.candidates)
    local deadline = GetGameTimer() + config().SpawnPointTimeoutMs
    while not request.done and GetGameTimer() < deadline do Wait(50) end
    spawnPointRequests[requestId] = nil
    return request.point
end

local function discard(record)
    if bodies[record.body_id] == record then bodies[record.body_id] = nil end
end

local function ownsPed(record, ped)
    return ped and DoesEntityExist(ped) and Entity(ped).state.humalike_body_id == record.body_id
end

local function deletePed(record)
    local ped = record.ped
    record.ped = nil
    -- Only the record's own ped is deleted; a recycled handle belongs to another.
    if ownsPed(record, ped) then DeleteEntity(ped) end
end

local function release(record, cause, bestEffort)
    if record.releasing then return end
    record.releasing = true
    record.status = 'released'
    record.release_cause = cause
    HumalikeHttp.PostAction('release_npc_body', {
        body_id = record.body_id,
        npc_id = record.npc_id,
        cause = cause,
    }, function(ok, _, body)
        record.releasing = false
        local finished = ok and type(body) == 'table'
            and (body.released == true or body.reason == 'not_owned')
        if finished then contact(GetGameTimer()) end
        if finished or bestEffort then
            discard(record)
            return
        end
        record.release_attempts = (record.release_attempts or 0) + 1
        if record.release_attempts >= config().ReleaseMaxAttempts then
            HumalikeDebug('population body %s release dropped after %d attempts',
                record.body_id, record.release_attempts)
            discard(record)
            return
        end
        record.release_retry_at = GetGameTimer() + backoff(record.release_attempts - 1)
    end)
end

-- The edge already dropped a forgotten body, so no release is posted.
local function retire(record, cause)
    deletePed(record)
    if record.forgotten then
        record.status = 'released'
        discard(record)
        return
    end
    release(record, cause)
end

local function keepReason(record)
    if HumalikeAmbientControlHeld and HumalikeAmbientControlHeld(record.network_id) then
        return 'held'
    end
    if record.npc_id and HumalikeWoundedStateOf and HumalikeWoundedStateOf(record.npc_id) then
        return 'wounded'
    end
    return nil
end

local function noteFailed(bodyId)
    if #failedBodies < 512 then failedBodies[#failedBodies + 1] = bodyId end
end

local function spawnFailed(record)
    deletePed(record)
    if record.status == 'released' then return end
    noteFailed(record.body_id)
    reportDirty = true
    if bodies[record.body_id] == record then retire(record, 'spawn_failed') end
end

function HumalikeNpcPopulation.Despawn(bodyId, cause)
    local record = bodies[bodyId]
    if not record or record.status == 'released' then return false end
    record.release_requested = cause or 'despawned'
    if record.status == 'spawning' then return false end
    local reason = keepReason(record)
    if reason ~= record.kept then reportDirty = true end
    record.kept = reason
    if reason then return false end
    retire(record, record.release_requested)
    reportDirty = true
    return true
end

local function bind(record)
    local ped = record.ped
    local coords = GetEntityCoords(ped)
    HumalikeHttp.PostAction('bind_npc_body', {
        body_id = record.body_id,
        npc_id = record.npc_id,
        entity_id = record.network_id,
        model_hash = HumalikeUnsignedHash(GetEntityModel(ped)),
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = GetEntityHeading(ped),
        zone_code = record.zone_code,
        routing_bucket = record.routing_bucket,
    }, function(ok, status, body)
        if bodies[record.body_id] ~= record or record.status ~= 'spawning' then
            if ownsPed(record, ped) then DeleteEntity(ped) end
            return
        end
        if not ok or type(body) ~= 'table' or body.status ~= 'bound' then
            HumalikeDebug('population body %s bind failed: %s', record.body_id,
                tostring(type(body) == 'table' and (body.reason or body.status) or status))
            spawnFailed(record)
            return
        end
        contact(GetGameTimer())
        record.status = 'bound'
        record.bound_at = GetGameTimer()
        record.lease_missing_since = record.bound_at
        reportDirty = true
        if record.release_requested then
            HumalikeNpcPopulation.Despawn(record.body_id, record.release_requested)
        end
    end)
end

function HumalikeNpcPopulation.Spawn(wanted)
    if bodies[wanted.body_id] then return false end
    local record = {
        body_id = wanted.body_id,
        kind = wanted.kind == 'extra' and 'extra' or 'persona',
        npc_id = wanted.npc_id,
        model = wanted.model,
        style_seed = wanted.style_seed,
        behaviour = wanted.behaviour or 'wander',
        scenario = wanted.scenario,
        walk_rate = wanted.walk_rate or 1.0,
        routing_bucket = wanted.routing_bucket,
        zone_code = wanted.zone_code,
        candidates = wanted.candidates,
        anchor_session_id = wanted.anchor_session_id,
        status = 'spawning',
        started_at = GetGameTimer(),
    }
    bodies[wanted.body_id] = record
    CreateThread(function()
        local point = resolveSpawnPoint(record)
        if bodies[record.body_id] ~= record then return end
        if record.release_requested then
            retire(record, record.release_requested)
            return
        end
        if not point then
            HumalikeDebug('population body %s has no pavement near any candidate', record.body_id)
            spawnFailed(record)
            return
        end
        local ped = CreatePed(4, GetHashKey(record.model), point.x, point.y, point.z,
            point.heading or 0.0, true, true)
        if not ped or ped <= 0 then
            spawnFailed(record)
            return
        end
        record.ped = ped
        SetEntityRoutingBucket(ped, record.routing_bucket)
        SetEntityOrphanMode(ped, 2)
        local state = Entity(ped).state
        state:set('humalike_npc_kind', 'population', true)
        state:set('humalike_body_kind', record.kind, true)
        state:set('humalike_body_id', record.body_id, true)
        state:set('humalike_body_behaviour', record.behaviour, true)
        state:set('humalike_body_scenario', record.scenario, true)
        state:set('humalike_walk_rate', record.walk_rate, true)
        if record.kind == 'extra' then state:set('humalike_style_seed', record.style_seed, true) end
        local networkId = NetworkGetNetworkIdFromEntity(ped)
        local attempts = 0
        while networkId <= 0 and attempts < 50 do
            Wait(0)
            attempts = attempts + 1
            networkId = NetworkGetNetworkIdFromEntity(ped)
        end
        if networkId <= 0 or bodies[record.body_id] ~= record or record.status ~= 'spawning' then
            spawnFailed(record)
            return
        end
        record.network_id = networkId
        if record.kind == 'extra' then
            record.status = 'extra'
            reportDirty = true
            if record.release_requested then
                HumalikeNpcPopulation.Despawn(record.body_id, record.release_requested)
            end
            return
        end
        bind(record)
    end)
    return true
end

local function forget(bodyId)
    local record = bodies[bodyId]
    if not record or record.status == 'released' then return end
    record.forgotten = true
    HumalikeNpcPopulation.Despawn(bodyId, 'despawned')
end

function HumalikeNpcPopulation.Report()
    if reportInFlight then
        reportDirty = true
        return false
    end
    reportDirty = false
    reportInFlight = true
    reportStartedAt = GetGameTimer()
    lastReportAt = reportStartedAt
    reportGeneration = reportGeneration + 1
    local generation = reportGeneration
    local spawned = {}
    for bodyId, record in pairs(bodies) do
        if record.status == 'bound' or record.status == 'extra' then
            spawned[#spawned + 1] = bodyId
        end
    end
    table.sort(spawned)
    local failed = failedBodies
    failedBodies = {}
    HumalikeHttp.PostAction('report_npc_bodies', {
        revision = math.max(planRevision, 0),
        spawned = spawned,
        failed = failed,
    }, function(ok, _, body)
        -- An answer to a report the tick already gave up on is stale.
        if generation ~= reportGeneration then return end
        reportInFlight = false
        if ok then
            reportFailures = 0
            contact(GetGameTimer())
            for _, bodyId in ipairs(type(body) == 'table' and body.unknown or {}) do
                if type(bodyId) == 'string' then forget(bodyId) end
            end
            return
        end
        for _, bodyId in ipairs(failed) do noteFailed(bodyId) end
        reportRetryAt = GetGameTimer() + backoff(reportFailures)
        reportFailures = reportFailures + 1
        reportDirty = true
    end)
    return true
end

function HumalikeNpcPopulation.ApplyPlan(body)
    local revision = tonumber(type(body) == 'table' and body.revision or nil)
    if not revision then return false, 'invalid' end
    if revision <= planRevision then return false, 'stale' end
    planRevision = revision
    enabled = body.enabled == true
    copsAllowed = copsConvar()
    contact(GetGameTimer())
    publishState()
    local wanted = {}
    if enabled and type(body.wanted) == 'table' then
        for _, planned in ipairs(body.wanted) do
            if validBody(planned) then
                wanted[planned.body_id] = planned
            else
                local bodyId = type(planned) == 'table' and planned.body_id or nil
                HumalikeDebug('population body rejected: %s', tostring(bodyId))
                if type(bodyId) == 'string' then noteFailed(bodyId) end
            end
        end
    end
    local released = {}
    for _, bodyId in ipairs(type(body.released) == 'table' and body.released or {}) do
        if type(bodyId) == 'string' then released[bodyId] = true end
    end
    for bodyId, record in pairs(bodies) do
        if released[bodyId] or not wanted[bodyId] then
            HumalikeNpcPopulation.Despawn(bodyId, 'despawned')
        elseif record.release_requested and record.status ~= 'released' then
            record.release_requested, record.kept, record.forgotten = nil, nil, nil
        end
    end
    for bodyId, planned in pairs(wanted) do
        if not bodies[bodyId] and not released[bodyId] then HumalikeNpcPopulation.Spawn(planned) end
    end
    reportFailures, reportRetryAt = 0, 0
    HumalikeNpcPopulation.Report()
    return true
end

function HumalikeNpcPopulation.Clear()
    for bodyId in pairs(bodies) do
        HumalikeNpcPopulation.Despawn(bodyId, 'despawned')
    end
    enabled = false
    publishState()
end

function HumalikeNpcPopulation.Reconcile()
    local now = GetGameTimer()
    local cfg = config()
    for bodyId, record in pairs(bodies) do
        if record.status == 'released' then
            if not record.releasing and now >= (record.release_retry_at or 0) then
                release(record, record.release_cause or 'despawned')
            end
        elseif record.status == 'spawning' then
            if record.release_requested then
                retire(record, record.release_requested)
                reportDirty = true
            elseif now - record.started_at > cfg.SpawnTimeoutMs then
                spawnFailed(record)
            end
        elseif record.status == 'bound' or record.status == 'extra' then
            if not ownsPed(record, record.ped) then
                record.ped = nil
                retire(record, 'despawned')
                reportDirty = true
            elseif record.release_requested then
                HumalikeNpcPopulation.Despawn(bodyId, record.release_requested)
            elseif record.status == 'bound' then
                local lease = HumalikeFindAmbientLease
                    and HumalikeFindAmbientLease(record.npc_id) or nil
                if lease and lease.entity_id == record.network_id then
                    record.lease_missing_since = nil
                elseif not record.lease_missing_since then
                    record.lease_missing_since = now
                elseif now - record.lease_missing_since > cfg.LeaseGraceMs then
                    HumalikeNpcPopulation.Despawn(bodyId, lease and 'kept_elsewhere' or 'despawned')
                end
            end
        end
    end
    copsAllowed = copsConvar()
    edgeLost = enabled and lastContactAt ~= nil
        and now - lastContactAt > cfg.HeartbeatMs * cfg.EdgeLostHeartbeats
    publishState()
    if lastReportAt and now - lastReportAt >= cfg.HeartbeatMs then reportDirty = true end
    -- A request that never calls back must not block reports until restart.
    if reportInFlight and now - reportStartedAt > cfg.RetryBackoffCapMs * 2 then
        reportInFlight = false
        reportDirty = true
    end
    if reportDirty and not reportInFlight and now >= reportRetryAt then
        HumalikeNpcPopulation.Report()
    end
end

function HumalikeNpcPopulation.Bodies()
    local rows = {}
    for bodyId, record in pairs(bodies) do
        rows[#rows + 1] = {
            body_id = bodyId,
            kind = record.kind,
            npc_id = record.npc_id,
            status = record.status,
            kept = record.kept,
            handle = record.ped,
            network_id = record.network_id,
            routing_bucket = record.routing_bucket,
        }
    end
    table.sort(rows, function(left, right) return left.body_id < right.body_id end)
    return rows
end

function HumalikeNpcPopulation.Enabled()
    return enabled and not edgeLost
end

function HumalikeNpcPopulation.SendState(playerId)
    TriggerClientEvent('humalike:npc:populationState', playerId, statePayload())
end

RegisterNetEvent('humalike:npc:populationSpawnPointResult')
AddEventHandler('humalike:npc:populationSpawnPointResult', function(requestId, point)
    local source = source
    local request = type(requestId) == 'string' and spawnPointRequests[requestId] or nil
    if not request or request.player_id ~= source or request.done then return end
    request.done = true
    if not validPoint(point) then return end
    local tolerance = config().SpawnPointTolerance
    for _, candidate in ipairs(request.candidates) do
        if HumalikeDistanceSquared(candidate, point) <= tolerance * tolerance then
            request.point = {
                x = point.x,
                y = point.y,
                z = point.z,
                heading = point.heading or candidate.heading or 0.0,
            }
            return
        end
    end
end)

CreateThread(function()
    while true do
        Wait(config().ReconcileTickMs)
        HumalikeNpcPopulation.Reconcile()
    end
end)

-- Revision 0 with nothing spawned makes the edge re-push the plan.
AddEventHandler('humalike:core:ready', function()
    HumalikeNpcPopulation.Report()
end)

-- Runs before core clears the credentials; onResourceStop only sweeps what is left.
AddEventHandler('humalike:core:stopping', function()
    for _, record in pairs(bodies) do
        deletePed(record)
        record.release_requested = record.release_requested or 'resource_stop'
        if not record.releasing then release(record, 'resource_stop', true) end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, record in pairs(bodies) do deletePed(record) end
end)
