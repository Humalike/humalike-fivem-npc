HumalikeNpcRuntimeControl = HumalikeNpcRuntimeControl or {}

local VALID_DOMAINS = {
    movement = true, animation = true, speech = true, perception = true, all = true,
}
local ACTION_DOMAINS = {
    follow_player = 'movement', stop_following = 'movement', hold_position = 'movement',
    release_movement = 'movement', enter_vehicle = 'movement', exit_vehicle = 'movement',
    walk_away = 'movement', run_away = 'movement', approach_player = 'movement',
    sit_down = 'movement', wave = 'animation', start_dancing = 'animation',
    interrupt_animation = 'animation', kneel = 'animation', hands_up = 'animation',
    punch = 'animation', stand_up = 'animation', hand_over_money = 'animation',
}
local DEFAULT_TTL_MS, MIN_TTL_MS, MAX_TTL_MS = 30000, 1000, 300000

local leases, domainsByNpc = {}, {}
local sequence, clientRevision = 0, 0

local function nowMs() return GetGameTimer() end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function targetForNpc(npcId)
    local persistent = NpcRegistry and NpcRegistry[npcId] or nil
    if persistent and persistent.type == 'external' then
        local entity = HumalikeNpcEntityOwnership
            and HumalikeNpcEntityOwnership.ExternalEntity(npcId) or nil
        if entity then
            persistent.entity_id = entity
            persistent.network_id = NetworkGetNetworkIdFromEntity(entity)
            return 'external', persistent, nil
        end
        return nil
    end
    if persistent and persistent.type == 'static' then
        local entity = persistent.entity_id
        if entity and DoesEntityExist(entity) then return 'static', persistent, nil end
        return nil
    end
    local ambient = HumalikeFindAmbientLease and HumalikeFindAmbientLease(npcId) or nil
    if ambient then return 'ambient', ambient, ambient.lease_token end
    return nil
end

local function normalizeDomains(value)
    if type(value) ~= 'table' or #value == 0 or #value > 5 then
        return nil, 'invalid_domains'
    end
    local result, seen = {}, {}
    for _, domain in ipairs(value) do
        if type(domain) ~= 'string' or not VALID_DOMAINS[domain] then
            return nil, 'invalid_domain'
        end
        if not seen[domain] then
            seen[domain] = true
            result[#result + 1] = domain
        end
    end
    table.sort(result)
    if seen.all and #result > 1 then return nil, 'all_domain_must_be_exclusive' end
    return result
end

local function normalizeTtl(value)
    local ttl = tonumber(value or DEFAULT_TTL_MS)
    if not ttl or ttl % 1 ~= 0 or ttl < MIN_TTL_MS or ttl > MAX_TTL_MS then return nil end
    return ttl
end

local function currentDomains(npcId) return domainsByNpc[npcId] or {} end

local function conflicts(npcId, requested)
    local held = currentDomains(npcId)
    if held.all then return true end
    for _, domain in ipairs(requested) do
        if domain == 'all' then
            if next(held) ~= nil then return true end
        elseif held[domain] then return true end
    end
    return false
end

local function publicDomains()
    local result = {}
    for npcId, held in pairs(domainsByNpc) do
        local domains = {}
        for domain in pairs(held) do domains[domain] = true end
        result[npcId] = domains
    end
    return result
end

function HumalikeNpcRuntimeControl.EdgeControls()
    local npcs = {}
    for npcId, held in pairs(domainsByNpc) do
        local domains = {}
        for domain in pairs(held) do domains[#domains + 1] = domain end
        table.sort(domains)
        npcs[#npcs + 1] = { npc_id = npcId, domains = domains }
    end
    table.sort(npcs, function(left, right) return left.npc_id < right.npc_id end)
    return npcs
end

local function publish()
    clientRevision = clientRevision + 1
    TriggerClientEvent('humalike:npc:runtimeControlSnapshot', -1, clientRevision, publicDomains())
    HumalikeNpcRuntimeState.Publish()
end

local function releaseLease(lease)
    if not lease or leases[lease.id] ~= lease then return false end
    leases[lease.id] = nil
    local held = domainsByNpc[lease.npcId]
    if held then
        for _, domain in ipairs(lease.domains) do
            if held[domain] == lease.id then held[domain] = nil end
        end
        if next(held) == nil then domainsByNpc[lease.npcId] = nil end
    end
    return true
end

local function invokingOwner()
    local owner = GetInvokingResource()
    if not owner or owner == GetCurrentResourceName() then return nil end
    return owner
end

local function acquire(npcId, options, owner)
    if type(npcId) ~= 'string' or npcId == '' or #npcId > 64 then
        return nil, 'invalid_npc_id'
    end
    local kind, _, incarnation = targetForNpc(npcId)
    if not kind then return nil, 'npc_not_active' end
    options = options or {}
    if type(options) ~= 'table' then return nil, 'invalid_options' end
    local requested, domainError = normalizeDomains(options.domains)
    if not requested then return nil, domainError end
    local ttl = normalizeTtl(options.ttlMs)
    if not ttl then return nil, 'invalid_ttl' end
    if options.reason ~= nil and (type(options.reason) ~= 'string'
        or #options.reason > 128) then return nil, 'invalid_reason' end
    if conflicts(npcId, requested) then return nil, 'domain_conflict' end

    sequence = sequence + 1
    local credentials = HumaLike.RuntimeCredentials()
    local lease = {
        id = ('%s:%s:%d'):format(owner, credentials and credentials.bootId or 'boot', sequence),
        npcId = npcId, kind = kind, ownerResource = owner, domains = requested,
        reason = options.reason, expiresAtMs = nowMs() + ttl, incarnation = incarnation,
    }
    leases[lease.id] = lease
    local held = domainsByNpc[npcId] or {}
    domainsByNpc[npcId] = held
    for _, domain in ipairs(requested) do held[domain] = lease.id end
    HumalikeNpcRuntimeControl.NeutralizeAction(npcId, requested)
    publish()
    local result = copy(lease)
    result.expiresInMs, result.expiresAtMs, result.incarnation = ttl, nil, nil
    return result
end

function HumalikeNpcRuntimeControl.NeutralizeAction(npcId, domains)
    local controlled = {}
    for _, domain in ipairs(domains) do controlled[domain] = true end
    if controlled.animation or controlled.all then
        if ForgetNpcPose then ForgetNpcPose(npcId) end
    end

    local kind, target = targetForNpc(npcId)
    if not kind then return end
    local entity = kind == 'ambient' and target.entity_handle or target.entity_id
    if kind == 'ambient' and (not entity or not DoesEntityExist(entity))
        and HumalikeResolveAmbientEntity then
        entity = HumalikeResolveAmbientEntity(target.entity_id)
    end
    if not entity or not DoesEntityExist(entity) then return end
    local action = Entity(entity).state.humalike_action
    local domain = type(action) == 'table' and ACTION_DOMAINS[action.key] or nil
    if domain and (controlled.all or controlled[domain]) then
        Entity(entity).state:set('humalike_action', nil, true)
    end
end

function HumalikeNpcRuntimeControl.AllowsAction(npcId, action)
    local held = currentDomains(npcId)
    if held.all then return false, 'npc_controlled' end
    local domain = ACTION_DOMAINS[action]
    if domain and held[domain] then return false, 'npc_domain_controlled' end
    return true
end

function HumalikeNpcRuntimeControl.State(npcId)
    local kind, target = targetForNpc(npcId)
    local definition = NpcRegistry and NpcRegistry[npcId] or nil
    if not kind and not definition then return nil, 'npc_not_found' end
    if not kind then
        kind, target = definition.type, definition
    end
    local entity = kind == 'ambient' and target.entity_handle or target.entity_id
    if kind == 'ambient' and (not entity or not DoesEntityExist(entity))
        and HumalikeResolveAmbientEntity then entity = HumalikeResolveAmbientEntity(target.entity_id) end
    local controlled = {}
    for domain, leaseId in pairs(currentDomains(npcId)) do
        local lease = leases[leaseId]
        if lease then
            controlled[domain] = {
                leaseId = lease.id, ownerResource = lease.ownerResource,
                expiresInMs = math.max(0, lease.expiresAtMs - nowMs()),
            }
        end
    end
    local exists = entity ~= nil and entity > 0 and DoesEntityExist(entity)
    local fullyControlled = controlled.all ~= nil or (
        controlled.movement ~= nil and controlled.animation ~= nil
        and controlled.speech ~= nil and controlled.perception ~= nil
    )
    local ownership = kind ~= 'ambient' and HumalikeNpcEntityOwnership
        and HumalikeNpcEntityOwnership.State(npcId) or nil
    return {
        apiVersion = 1, npcId = npcId, kind = kind, active = exists,
        entity = entity,
        networkId = target.network_id or (kind == 'ambient' and target.entity_id or nil),
        routingBucket = exists and GetEntityRoutingBucket(entity)
            or ownership and ownership.routingBucket or target.routing_bucket,
        modelHash = exists and GetEntityModel(entity) or nil,
        aiEnabled = exists and not fullyControlled, controlledDomains = controlled,
        entityOwner = ownership and ownership.entityOwner or 'humalike',
        bindingId = ownership and ownership.bindingId or nil,
        despawnId = ownership and ownership.despawnId or nil,
        entityOwnerResource = ownership and ownership.ownerResource or nil,
    }
end

exports('GetNpcRuntimeState', function(npcId)
    local state, err = HumalikeNpcRuntimeControl.State(npcId)
    if not state then return HumalikeExportResult.Failure(err) end
    return HumalikeExportResult.Success(copy(state))
end)

exports('ListNpcRuntimeStates', function()
    local rows = {}
    for npcId, definition in pairs(NpcRegistry or {}) do
        local state = HumalikeNpcRuntimeControl.State(npcId)
        if state then
            state.name = definition.name
            state.model = definition.model
            rows[#rows + 1] = copy(state)
        end
    end
    local seen = {}
    for _, row in ipairs(rows) do seen[row.npcId] = true end
    for _, lease in pairs(AmbientNpcLeases or {}) do
        if not seen[lease.npc_id] then
            local state = HumalikeNpcRuntimeControl.State(lease.npc_id)
            if state and state.kind == 'ambient' then
                state.name = 'Dynamic NPC'
                state.model = state.modelHash and tostring(state.modelHash) or nil
                rows[#rows + 1] = copy(state)
                seen[lease.npc_id] = true
            end
        end
    end
    table.sort(rows, function(left, right) return left.npcId < right.npcId end)
    return HumalikeExportResult.Success(rows)
end)

exports('AcquireNpcControl', function(npcId, options)
    local owner = invokingOwner()
    if not owner then return HumalikeExportResult.Failure('external_resource_required') end
    local lease, err = acquire(npcId, options, owner)
    if not lease then return HumalikeExportResult.Failure(err) end
    return HumalikeExportResult.Success(lease)
end)

exports('RenewNpcControl', function(leaseId, ttlMs)
    local owner = invokingOwner()
    if not owner then return HumalikeExportResult.Failure('external_resource_required') end
    local lease = type(leaseId) == 'string' and leases[leaseId] or nil
    if not lease then return HumalikeExportResult.Failure('lease_not_found') end
    if lease.ownerResource ~= owner then return HumalikeExportResult.Failure('not_owner') end
    local ttl = normalizeTtl(ttlMs)
    if not ttl then return HumalikeExportResult.Failure('invalid_ttl') end
    lease.expiresAtMs = nowMs() + ttl
    local result = copy(lease)
    result.expiresInMs, result.expiresAtMs, result.incarnation = ttl, nil, nil
    return HumalikeExportResult.Success(result)
end)

exports('ReleaseNpcControl', function(leaseId)
    local owner = invokingOwner()
    if not owner then return HumalikeExportResult.Failure('external_resource_required') end
    local lease = type(leaseId) == 'string' and leases[leaseId] or nil
    if not lease then return HumalikeExportResult.Failure('lease_not_found') end
    if lease.ownerResource ~= owner then return HumalikeExportResult.Failure('not_owner') end
    releaseLease(lease)
    publish()
    return HumalikeExportResult.Success()
end)

RegisterNetEvent('humalike:npc:requestRuntimeControls')
AddEventHandler('humalike:npc:requestRuntimeControls', function()
    TriggerClientEvent('humalike:npc:runtimeControlSnapshot', source, clientRevision, publicDomains())
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    local changed = false
    for leaseId, lease in pairs(copy(leases)) do
        if lease.ownerResource == resourceName then
            changed = releaseLease(leases[leaseId]) or changed
        end
    end
    if changed then publish() end
end)

CreateThread(function()
    while true do
        Wait(500)
        local changed, now = false, nowMs()
        for leaseId, lease in pairs(copy(leases)) do
            local current = leases[leaseId]
            local kind, _, incarnation = targetForNpc(lease.npcId)
            if current and (current.expiresAtMs <= now
                or kind == nil
                or (current.kind == 'ambient' and incarnation ~= current.incarnation)) then
                changed = releaseLease(current) or changed
            end
        end
        if changed then publish() end
    end
end)
