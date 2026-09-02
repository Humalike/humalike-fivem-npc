local testNpcs, testLeases = {}, {}

local function reply(source, message)
    print(('[humalike-control-test] %s'):format(message))
    if source > 0 then
        TriggerClientEvent('chat:addMessage', source, { args = { 'HumaLike test', message } })
    end
end

local function cleanup(npcId, removePed)
    local record = testNpcs[npcId]
    if not record then return false end
    if record.bindingId then exports.humalike:UnbindNpcEntity(record.bindingId) end
    if removePed and record.entity and DoesEntityExist(record.entity) then
        DeleteEntity(record.entity)
    end
    testNpcs[npcId] = nil
    return true
end

local function bind(source, npcId, model)
    if source <= 0 then return reply(source, 'bind requires an in-game player') end
    cleanup(npcId, true)
    local playerPed = GetPlayerPed(source)
    if playerPed == 0 then return reply(source, 'player ped unavailable') end
    local coords = GetEntityCoords(playerPed)
    local entity = CreatePed(4, GetHashKey(model), coords.x + 2.0, coords.y, coords.z,
        GetEntityHeading(playerPed), true, true)
    if entity == 0 then return reply(source, 'CreatePed failed') end
    SetEntityRoutingBucket(entity, GetPlayerRoutingBucket(source))
    SetEntityOrphanMode(entity, 2)
    local networkId = NetworkGetNetworkIdFromEntity(entity)
    local attempts = 0
    while networkId <= 0 and attempts < 50 do
        Wait(0)
        attempts = attempts + 1
        networkId = NetworkGetNetworkIdFromEntity(entity)
    end
    if networkId <= 0 then
        DeleteEntity(entity)
        return reply(source, 'network ID unavailable')
    end
    local binding, err = exports.humalike:BindNpcEntity(npcId, networkId, {
        routingBucket = GetPlayerRoutingBucket(source),
    })
    if not binding then
        DeleteEntity(entity)
        return reply(source, ('bind failed: %s'):format(tostring(err)))
    end
    testNpcs[npcId] = { entity = entity, networkId = networkId, bindingId = binding.id }
    reply(source, ('bound %s to network %d'):format(npcId, networkId))
end

local function rebind()
    for npcId, record in pairs(testNpcs) do
        if record.entity and DoesEntityExist(record.entity) then
            local binding = exports.humalike:BindNpcEntity(npcId, record.networkId, {
                routingBucket = GetEntityRoutingBucket(record.entity),
            })
            record.bindingId = binding and binding.id or nil
        end
    end
end

RegisterCommand('humalike_npc_test', function(source, args)
    local operation, npcId = args[1], args[2]
    if operation == 'bind' and npcId and args[3] then
        bind(source, npcId, args[3])
    elseif operation == 'unbind' and npcId then
        local record = testNpcs[npcId]
        if record and record.bindingId then
            local ok, err = exports.humalike:UnbindNpcEntity(record.bindingId)
            if ok then record.bindingId = nil end
            reply(source, ok and 'unbound' or ('failed: ' .. tostring(err)))
        else
            reply(source, 'no test binding')
        end
    elseif operation == 'delete' and npcId then
        local record = testNpcs[npcId]
        if record and record.entity and DoesEntityExist(record.entity) then
            DeleteEntity(record.entity)
            testNpcs[npcId] = nil
            reply(source, 'external ped deleted; NPC is now offline')
        else
            reply(source, 'no external ped')
        end
    elseif operation == 'despawn' and npcId then
        local result, err = exports.humalike:DespawnNpc(npcId)
        reply(source, result and ('despawned: ' .. result.id) or ('failed: ' .. tostring(err)))
    elseif operation == 'respawn' and npcId then
        local ok, err = exports.humalike:RespawnNpc(npcId)
        reply(source, ok and 'respawned' or ('failed: ' .. tostring(err)))
    elseif operation == 'state' and npcId then
        local state, err = exports.humalike:GetNpcRuntimeState(npcId)
        reply(source, state and json.encode(state) or ('failed: ' .. tostring(err)))
    elseif operation == 'control' and npcId and args[3] then
        local domains = {}
        for domain in args[3]:gmatch('[^,]+') do domains[#domains + 1] = domain end
        local lease, err = exports.humalike:AcquireNpcControl(npcId, {
            domains = domains, ttlMs = tonumber(args[4]) or 30000,
            reason = 'manual_test',
        })
        if lease then testLeases[npcId] = lease.id end
        reply(source, lease and ('lease: ' .. lease.id) or ('failed: ' .. tostring(err)))
    elseif operation == 'release' and npcId then
        local leaseId = testLeases[npcId]
        local ok, err
        if leaseId then ok, err = exports.humalike:ReleaseNpcControl(leaseId) end
        if ok then testLeases[npcId] = nil end
        reply(source, ok and 'lease released' or ('failed: ' .. tostring(err)))
    else
        reply(source, 'usage: /humalike_npc_test <bind|unbind|delete|despawn|respawn|state|control|release> <npcId> [value]')
    end
end, true)

AddEventHandler('humalike:npc:ready', rebind)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    for npcId in pairs(testNpcs) do cleanup(npcId, true) end
    for npcId, leaseId in pairs(testLeases) do
        exports.humalike:ReleaseNpcControl(leaseId)
        testLeases[npcId] = nil
    end
end)
