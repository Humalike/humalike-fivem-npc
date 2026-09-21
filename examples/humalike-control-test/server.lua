local testNpcs, testLeases, busy, lastRequests = {}, {}, {}, {}
local ACE = 'command.humalike_npc_test'

local function result(ok, message) return { ok = ok, message = message } end
local function call(name, ...)
    local args = table.pack(...)
    local ok, value = pcall(function()
        return exports.humalike[name](exports.humalike, table.unpack(args, 1, args.n))
    end)
    if not ok or type(value) ~= 'table' or type(value.ok) ~= 'boolean' then
        return { ok = false, error = 'humalike_unavailable_or_outdated' }
    end
    return value
end

local function exists(record)
    return record and record.entity and DoesEntityExist(record.entity)
        and NetworkGetNetworkIdFromEntity(record.entity) == record.networkId
end

local function release(npcId)
    local id = testLeases[npcId]
    if not id then return result(false, 'test_lease_not_found') end
    local response = call('ReleaseNpcControl', id)
    if response.ok or response.error == 'lease_not_found' then testLeases[npcId] = nil end
    return result(response.ok, response.ok and 'Control released' or response.error)
end

local function cleanup(npcId)
    local record = testNpcs[npcId]
    if record then
        if record.bindingId then call('UnbindNpcEntity', record.bindingId) end
        if exists(record) then DeleteEntity(record.entity) end
    end
    testNpcs[npcId] = nil
    if testLeases[npcId] then release(npcId) end
end

local function near(source, record)
    if not exists(record) then return true end
    local player = GetPlayerPed(source)
    if player == 0 or GetEntityRoutingBucket(record.entity) ~= GetPlayerRoutingBucket(source) then
        return false
    end
    local a, b = GetEntityCoords(player), GetEntityCoords(record.entity)
    return (a.x-b.x)^2 + (a.y-b.y)^2 + (a.z-b.z)^2 <= 2500
end

local function targetEntity(state)
    if state.active and state.entity and state.networkId and DoesEntityExist(state.entity)
        and NetworkGetNetworkIdFromEntity(state.entity) == state.networkId then
        return state.entity
    end
    local record = testNpcs[state.npcId]
    if exists(record) then return record.entity end
end

local function teleport(source, npcId)
    local response = call('GetNpcRuntimeState', npcId)
    if not response.ok then return result(false, response.error) end
    local state = response.value
    if state.kind ~= 'external' and state.kind ~= 'static' and state.kind ~= 'ambient' then return result(false, 'unsupported_npc_kind') end
    local entity = targetEntity(state)
    if not entity then return result(false, 'npc_ped_unavailable') end
    local player = GetPlayerPed(source)
    if player == 0 or not DoesEntityExist(player) then return result(false, 'player_ped_unavailable') end
    if GetVehiclePedIsIn(player, false) ~= 0 then return result(false, 'exit_vehicle_before_teleport') end
    local coords = GetEntityCoords(entity)
    SetPlayerRoutingBucket(source, GetEntityRoutingBucket(entity))
    SetEntityCoords(player, coords.x + 2.0, coords.y, coords.z + 0.3, false, false, false, false)
    return result(true, 'Teleported next to NPC')
end

local function roster()
    local response = call('ListNpcRuntimeStates')
    if not response.ok then return nil, response.error end
    local rows = {}
    for _, state in ipairs(response.value) do
        if state.kind == 'external' or state.kind == 'static' or state.kind == 'ambient' then
            local record = testNpcs[state.npcId]
            local pedExists = exists(record) == true
            local domains = {}
            local ownsLease = false
            for name, lease in pairs(state.controlledDomains or {}) do
                domains[#domains + 1] = name
                if lease.leaseId == testLeases[state.npcId] then ownsLease = true end
            end
            if not ownsLease then testLeases[state.npcId] = nil end
            table.sort(domains)
            rows[#rows + 1] = {
                npcId = state.npcId, kind = state.kind == 'ambient' and 'dynamic' or state.kind, canTeleport = targetEntity(state) ~= nil, name = state.name or state.npcId, model = state.model,
                active = state.active, aiEnabled = state.aiEnabled,
                networkId = state.networkId, routingBucket = state.routingBucket,
                owner = state.entityOwnerResource, testPed = pedExists,
                bound = state.active and state.bindingId ~= nil,
                canUnbind = pedExists and record.bindingId ~= nil,
                canRelease = testLeases[state.npcId] ~= nil,
                domains = domains,
            }
        end
    end
    return rows
end

local function bind(source, npcId, model)
    if source <= 0 then return result(false, 'bind_requires_in_game_player') end
    local current = call('GetNpcRuntimeState', npcId)
    if not current.ok then return result(false, current.error) end
    if current.value.kind ~= 'external' then return result(false, 'npc_not_external') end
    if current.value.active and current.value.entityOwnerResource ~= GetCurrentResourceName() then
        return result(false, 'ped_owned_by_another_resource')
    end
    if not near(source, testNpcs[npcId]) then return result(false, 'ped_too_far_or_other_bucket') end
    local playerPed = GetPlayerPed(source)
    if playerPed == 0 then return result(false, 'player_ped_unavailable') end
    cleanup(npcId)
    local coords = GetEntityCoords(playerPed)
    local entity = CreatePed(4, GetHashKey(model), coords.x + 2.0, coords.y, coords.z,
        GetEntityHeading(playerPed), true, true)
    if entity == 0 then return result(false, 'CreatePed_failed') end
    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(source))
    SetEntityOrphanMode(entity, 2)
    local networkId = NetworkGetNetworkIdFromEntity(entity)
    local attempts = 0
    while networkId <= 0 and attempts < 50 do
        Wait(0)
        attempts = attempts + 1
        networkId = NetworkGetNetworkIdFromEntity(entity)
    end
    if networkId <= 0 or GetPlayerPed(source) ~= playerPed then
        DeleteEntity(entity)
        return result(false, 'spawn_interrupted')
    end
    local response = call('BindNpcEntity', npcId, networkId, {
        routingBucket = GetPlayerRoutingBucket(source),
    })
    if not response.ok then
        DeleteEntity(entity)
        return result(false, response.error)
    end
    testNpcs[npcId] = { entity = entity, networkId = networkId, bindingId = response.value.id }
    return result(true, 'Ped spawned and bound')
end

local function perform(source, operation, npcId, value, ttl)
    if operation == 'teleport' then return teleport(source, npcId) end
    if operation == 'bind' then return bind(source, npcId, value) end
    local record = testNpcs[npcId]
    if source > 0 and not near(source, record) then
        return result(false, 'ped_too_far_or_other_bucket')
    end
    if operation == 'unbind' then
        if not record or not record.bindingId then return result(false, 'no_test_binding') end
        local response = call('UnbindNpcEntity', record.bindingId)
        if response.ok then record.bindingId = nil end
        return result(response.ok, response.ok and 'Unbound; ped remains in the world' or response.error)
    elseif operation == 'delete' then
        if not exists(record) then return result(false, 'no_test_ped') end
        DeleteEntity(record.entity)
        testNpcs[npcId] = nil
        if testLeases[npcId] then release(npcId) end
        return result(true, 'Ped deleted; automatic detachment pending')
    elseif operation == 'release' then
        return release(npcId)
    elseif operation == 'control' then
        local domains = {}
        for domain in (value or 'movement,animation'):gmatch('[^,]+') do domains[#domains+1] = domain end
        local response = call('AcquireNpcControl', npcId, {
            domains = domains, ttlMs = tonumber(ttl) or 30000, reason = 'manual_test',
        })
        if response.ok then testLeases[npcId] = response.value.id end
        return result(response.ok, response.ok and 'Control acquired for 30 seconds' or response.error)
    elseif operation == 'state' then
        local response = call('GetNpcRuntimeState', npcId)
        return result(response.ok, response.ok and json.encode(response.value) or response.error)
    elseif operation == 'despawn' or operation == 'respawn' then
        local response = call(operation == 'despawn' and 'DespawnNpc' or 'RespawnNpc', npcId)
        return result(response.ok, response.ok and operation or response.error)
    end
    return result(false, 'unknown_operation')
end

local function execute(source, operation, npcId, value, ttl)
    if type(npcId) ~= 'string' or npcId == '' or #npcId > 64 then return result(false, 'invalid_npc_id') end
    if busy[npcId] then return result(false, 'npc_busy') end
    busy[npcId] = true
    local ok, response = pcall(perform, source, operation, npcId, value, ttl)
    busy[npcId] = nil
    return ok and response or result(false, 'operation_failed')
end

RegisterCommand('humalike_npc_test', function(source, args)
    if source > 0 and not IsPlayerAceAllowed(source, ACE) then return end
    if (not args[1] or args[1] == 'panel') and source > 0 then
        TriggerClientEvent('humalike-control-test:open', source)
        return
    end
    local response = execute(source, args[1], args[2], args[3], args[4])
    print(('[humalike-control-test] %s'):format(response.message))
    if source > 0 then
        TriggerClientEvent('chat:addMessage', source, { args = { 'HumaLike test', response.message } })
    end
end, true)

local panelOperations = { teleport = true, bind = true, unbind = true, delete = true, control = true, release = true }
RegisterNetEvent('humalike-control-test:request', function(requestId, operation, npcId)
    local player = source
    if type(requestId) ~= 'number' or requestId % 1 ~= 0 or requestId < 1 or requestId > 2147483647 then return end
    local function respond(response)
        TriggerClientEvent('humalike-control-test:response', player, requestId, response)
    end
    if player <= 0 or not IsPlayerAceAllowed(player, ACE) then
        respond(result(false, 'permission_denied'))
        return
    end
    local now = GetGameTimer()
    if lastRequests[player] and now - lastRequests[player] < 250 then
        respond(result(false, 'rate_limited'))
        return
    end
    lastRequests[player] = now
    local rows, err = roster()
    if not rows then respond(result(false, err)); return end
    if operation == 'refresh' then respond({ ok = true, rows = rows }); return end
    if type(operation) ~= 'string' or not panelOperations[operation] then
        respond(result(false, 'unknown_operation')); return
    end
    local selected
    for _, row in ipairs(rows) do if row.npcId == npcId then selected = row; break end end
    if not selected then respond(result(false, 'npc_not_in_roster')); return end
    if operation ~= 'teleport' and selected.kind ~= 'external' then
        respond(result(false, 'npc_not_external')); return
    end
    if operation ~= 'bind' and operation ~= 'teleport' and not selected.testPed then
        respond(result(false, 'not_a_test_resource_ped')); return
    end
    if operation == 'bind' and (type(selected.model) ~= 'string' or selected.model == '') then
        respond(result(false, 'configured_model_missing')); return
    end
    local response = execute(player, operation, npcId, operation == 'bind' and selected.model or 'movement,animation', 30000)
    response.rows = roster()
    respond(response)
end)

AddEventHandler('playerDropped', function() lastRequests[source] = nil end)
AddEventHandler('humalike:npc:ready', function()
    for npcId, record in pairs(testNpcs) do
        if exists(record) then
            local response = call('BindNpcEntity', npcId, record.networkId, {
                routingBucket = GetEntityRoutingBucket(record.entity),
            })
            record.bindingId = response.ok and response.value.id or nil
        end
    end
end)
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for npcId in pairs(testNpcs) do cleanup(npcId) end
    for npcId in pairs(testLeases) do release(npcId) end
end)
