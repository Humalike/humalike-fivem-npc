
local enabled = GetConvar('humalike_developer_tools', '0') == '1'
local ttlSeconds = 1800
local debugSpawns = {}
local pendingSpawns = {}
local sequence = 0

local function reply(playerId, message)
    local text = ('[humalike-dev] %s'):format(message)
    if playerId == 0 then
        print(text)
        return
    end
    TriggerClientEvent('humalike:npc:developerReply', playerId, text)
end

local function allowed(playerId)
    if not enabled then
        reply(playerId, 'developer tools are disabled (set humalike_developer_tools 1)')
        return false
    end
    if playerId == 0 or not IsPlayerAceAllowed(playerId, 'humalike.developer_tools') then
        reply(playerId, 'missing ACE humalike.developer_tools')
        return false
    end
    return true
end

local function validNpcId(value)
    return type(value) == 'string'
        and value:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-'
            .. '%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$') ~= nil
end

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end

local function nextSpawnId(playerId)
    sequence = sequence + 1
    return ('%d-%d-%d-%d'):format(os.time(), GetGameTimer(), playerId, sequence)
end

local function leaseDetails(npcId, lease)
    lease = lease or {}
    local entity = lease.entity_handle or lease.ped
    local networkId = lease.network_id or lease.entity_id
    if type(entity) == 'number' and entity > 0 and DoesEntityExist(entity) then
        local coords = GetEntityCoords(entity)
        return ('coords=(%.2f, %.2f, %.2f) npc=%s entity=%d network=%s bucket=%s')
            :format(coords.x, coords.y, coords.z, npcId, entity, tostring(networkId),
                tostring(lease.routing_bucket))
    end
    return ('coords=unavailable npc=%s entity=%s network=%s bucket=%s')
        :format(npcId, tostring(entity), tostring(networkId), tostring(lease.routing_bucket))
end

local function existingLease(npcId, fallback)
    local lease = HumalikeFindAmbientLease and HumalikeFindAmbientLease(npcId) or nil
    return lease or fallback
end

local function replyAlreadyLeased(playerId, npcId, fallback)
    reply(playerId, ('already leased: %s; use /humalike_dev ambient goto %s')
        :format(leaseDetails(npcId, existingLease(npcId, fallback)), npcId))
end

local function discard(record, deletePed)
    if not record then return end
    if debugSpawns[record.npc_id] == record then debugSpawns[record.npc_id] = nil end
    record.releasing = false
    if deletePed and record.ped and DoesEntityExist(record.ped) then
        DeleteEntity(record.ped)
    end
end

local function release(record, deletePed, bestEffort, callback)
    if not record or record.releasing then return end
    record.releasing = true
    HumalikeHttp.PostAction('release_ambient_debug_spawn', {
        debug_spawn_id = record.debug_spawn_id,
        npc_id = record.npc_id,
    }, function(ok, status, body)
        local released = ok and type(body) == 'table' and body.released == true
        local alreadyGone = ok and type(body) == 'table'
            and body.released == false and body.reason == 'not_owned'
        local finished = released or alreadyGone
        if finished or bestEffort then discard(record, deletePed) else
            record.releasing = false
            local reason = type(body) == 'table' and body.reason or status
            reply(record.owner_source, ('release failed: %s; spawn kept for retry')
                :format(tostring(reason)))
        end
        if callback then callback(finished) end
    end)
end

local function bind(record)
    local ped = record.ped
    if not DoesEntityExist(ped) then
        release(record, false, true)
        return
    end
    local coords = GetEntityCoords(ped)
    local request = {
        assignment = HumaLike.EdgeAssignmentKey(),
    }
    record.bindingRequest = request
    HumalikeHttp.PostAction('bind_ambient_debug_spawn', {
        debug_spawn_id = record.debug_spawn_id,
        npc_id = record.npc_id,
        entity_id = record.network_id,
        model_hash = unsignedHash(GetEntityModel(ped)),
        x = coords.x,
        y = coords.y,
        z = coords.z,
        heading = GetEntityHeading(ped),
        routing_bucket = record.routing_bucket,
        ttl_seconds = ttlSeconds,
    }, function(ok, status, body)
        if debugSpawns[record.npc_id] ~= record
            or record.bindingRequest ~= request then return end
        record.bindingRequest = nil
        if not HumaLike.IsCurrentEdgeAssignment(request.assignment) then return end
        if not ok or type(body) ~= 'table' or body.status ~= 'bound' then
            local reason = type(body) == 'table' and (body.reason or body.status) or status
            release(record, true, true)
            reply(record.owner_source, ('spawn failed: %s'):format(tostring(reason)))
            return
        end
        reply(record.owner_source, ('spawned: %s; use /humalike_dev ambient goto %s')
            :format(leaseDetails(record.npc_id, record), record.npc_id))
    end)
end

local function spawn(playerId, npcId)
    local current = debugSpawns[npcId]
    if current and current.ped and DoesEntityExist(current.ped) then
        replyAlreadyLeased(playerId, npcId, current)
        return
    end
    if pendingSpawns[npcId] then
        reply(playerId, 'a spawn request for this NPC is already running')
        return
    end
    pendingSpawns[npcId] = true
    HumalikeHttp.PostAction('prepare_ambient_debug_spawn', { npc_id = npcId },
        function(ok, status, body)
            pendingSpawns[npcId] = nil
            if not ok or type(body) ~= 'table' then
                reply(playerId, ('prepare failed (HTTP %s)'):format(tostring(status)))
                return
            end
            if body.status == 'already_leased' then
                replyAlreadyLeased(playerId, npcId, body)
                return
            end
            if body.status ~= 'ready' or type(body.model) ~= 'string'
                or type(body.model_hash) ~= 'number' then
                reply(playerId, ('NPC unavailable: %s'):format(tostring(body.reason or body.status)))
                return
            end
            if not GetPlayerName(playerId)
                or not IsPlayerAceAllowed(playerId, 'humalike.developer_tools') then return end
            local playerPed = GetPlayerPed(playerId)
            if not playerPed or playerPed <= 0 or not DoesEntityExist(playerPed) then
                reply(playerId, 'player ped is unavailable')
                return
            end
            local coords = GetEntityCoords(playerPed)
            local heading = GetEntityHeading(playerPed)
            local radians = math.rad(heading)
            local x = coords.x - math.sin(radians) * 3.0
            local y = coords.y + math.cos(radians) * 3.0
            local ped = CreatePed(4, GetHashKey(body.model), x, y, coords.z, heading, true, true)
            if not ped or ped <= 0 then
                reply(playerId, 'CreatePed failed')
                return
            end
            local routingBucket = GetPlayerRoutingBucket(playerId)
            SetEntityRoutingBucket(ped, routingBucket)
            SetEntityOrphanMode(ped, 2)
            local spawnId = nextSpawnId(playerId)
            Entity(ped).state:set('humalike_debug_spawn_id', spawnId, true)
            local networkId = NetworkGetNetworkIdFromEntity(ped)
            local attempts = 0
            while networkId <= 0 and attempts < 50 do
                Wait(0)
                attempts = attempts + 1
                networkId = NetworkGetNetworkIdFromEntity(ped)
            end
            if networkId <= 0 then
                DeleteEntity(ped)
                reply(playerId, 'network registration failed')
                return
            end
            local record = {
                npc_id = npcId,
                debug_spawn_id = spawnId,
                ped = ped,
                network_id = networkId,
                routing_bucket = routingBucket,
                owner_source = playerId,
                expires_at = os.time() + ttlSeconds,
            }
            debugSpawns[npcId] = record
            bind(record)
        end)
end

local function gotoNpc(playerId, npcId)
    local lease = HumalikeFindAmbientLease and HumalikeFindAmbientLease(npcId) or nil
    local entity = lease and (lease.entity_handle
        or HumalikeResolveAmbientEntity and HumalikeResolveAmbientEntity(lease.entity_id)) or nil
    if not lease or not entity then
        reply(playerId, 'NPC has no active ambient lease')
        return
    end
    local playerBucket = GetPlayerRoutingBucket(playerId)
    if playerBucket ~= lease.routing_bucket then
        reply(playerId, ('NPC is in routing bucket %s; you are in %s')
            :format(tostring(lease.routing_bucket), tostring(playerBucket)))
        return
    end
    local networkId = lease.network_id or lease.entity_id
    if not networkId or networkId <= 0 then
        reply(playerId, 'NPC entity is not networked')
        return
    end
    reply(playerId, ('teleporting: %s'):format(leaseDetails(npcId, lease)))
    TriggerClientEvent('humalike:npc:developerGotoAmbient', playerId, networkId)
end

local function remove(playerId, npcId)
    local record = debugSpawns[npcId]
    if not record then
        reply(playerId, 'this NPC was not spawned by developer tools')
        return
    end
    release(record, true, false, function(released)
        if released then reply(playerId, ('removed debug spawn %s'):format(npcId)) end
    end)
end

local function list(playerId)
    local rows = {}
    for npcId, record in pairs(debugSpawns) do
        rows[#rows + 1] = ('%s expires_in=%ss'):format(
            leaseDetails(npcId, record), math.max(0, record.expires_at - os.time()))
    end
    table.sort(rows)
    if #rows == 0 then reply(playerId, 'no active debug spawns') return end
    for _, row in ipairs(rows) do reply(playerId, row) end
end

-- `/humalike_dev observe <npc_uuid> <key> [field=value ...]`: report a declared
-- observation without the inventory (or whatever) hook that would normally
-- fire it. Values are typed from the declaration, so `quantity=2` is an
-- integer and `stolen=true` a boolean.
local function observe(playerId, npcId, key, pairsList)
    local _, definition = HumalikeActions.Observation(key)
    if not definition then reply(playerId, ('unknown observation %s'):format(tostring(key))) return end
    local fields = {}
    for _, pair in ipairs(pairsList) do
        local name, raw = pair:match('^([^=]+)=(.*)$')
        local fieldType = name and definition.fields[name]
        if fieldType == 'integer' or fieldType == 'number' then fields[name] = tonumber(raw)
        elseif fieldType == 'boolean' then
            if raw ~= 'true' and raw ~= 'false' then
                reply(playerId, ('%s must be true or false'):format(name))
                return
            end
            fields[name] = raw == 'true'
        else fields[name or pair] = raw end
    end
    local result = HumalikeReportObservation(npcId, playerId, key, fields)
    if result.ok then
        reply(playerId, ('reported %s: %s'):format(result.value.key, result.value.text))
    else
        reply(playerId, ('observation rejected: %s'):format(result.error))
    end
end

local USAGE = 'usage: /humalike_dev ambient <spawn|goto|remove|list> [npc_uuid]'
    .. ' | observe <npc_uuid> <key> [field=value ...]'

RegisterCommand('humalike_dev', function(playerId, args)
    if not allowed(playerId) then return end
    if args[1] == 'observe' then
        if not validNpcId(args[2]) then reply(playerId, 'a canonical NPC UUID is required') return end
        observe(playerId, args[2], args[3], { table.unpack(args, 4) })
        return
    end
    if args[1] ~= 'ambient' then
        reply(playerId, USAGE)
        return
    end
    local operation, npcId = args[2], args[3]
    if operation == 'list' then list(playerId) return end
    if not validNpcId(npcId) then reply(playerId, 'a canonical NPC UUID is required') return end
    if operation == 'spawn' then spawn(playerId, npcId)
    elseif operation == 'goto' then gotoNpc(playerId, npcId)
    elseif operation == 'remove' then remove(playerId, npcId)
    else reply(playerId, USAGE) end
end, false)

CreateThread(function()
    while true do
        Wait(5000)
        local expired = {}
        for _, record in pairs(debugSpawns) do
            if record.expires_at <= os.time() or not DoesEntityExist(record.ped) then
                expired[#expired + 1] = record
            end
        end
        for _, record in ipairs(expired) do release(record, true, false) end
    end
end)

AddEventHandler('humalike:core:ready', function()
    for _, record in pairs(debugSpawns) do bind(record) end
end)

local function replayBindings()
    for _, record in pairs(debugSpawns) do bind(record) end
end

AddEventHandler('humalike:runtime:edgeChanged', replayBindings)
AddEventHandler('humalike:runtime:refreshed', function(runtime)
    if not runtime or runtime.edgeChanged ~= true then replayBindings() end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for _, record in pairs(debugSpawns) do
        if record.ped and DoesEntityExist(record.ped) then DeleteEntity(record.ped) end
        record.ped = nil
        release(record, false, true)
    end
end)
