AmbientPeds = {}
AmbientNpcEntries = {}

local discoveryRadius = Config.AmbientBootstrapRadius
local ambientEnabled = nil
local desiredAmbientLeases = {}
local voiceMuteRevision = -1
local rejectedPeds = {}

RegisterNetEvent('humalike:npc:voiceMuteSnapshot')
AddEventHandler('humalike:npc:voiceMuteSnapshot', function(revision, states)
    revision = tonumber(revision)
    if not revision or revision <= voiceMuteRevision or type(states) ~= 'table' then return end
    voiceMuteRevision = revision
    for npcId, entry in pairs(KnownNpcs or {}) do
        entry.voice_muted = states[npcId] == true
    end
    for npcId, entry in pairs(AmbientNpcEntries) do
        entry.voice_muted = states[npcId] == true
    end
end)

local function unsignedHash(value)
    return value < 0 and value + 4294967296 or value
end
local function networkIdFor(ped)
    if type(ped) ~= 'number' or ped <= 0 or not DoesEntityExist(ped)
        or not NetworkGetEntityIsNetworked(ped) then return nil end
    local networkId = NetworkGetNetworkIdFromEntity(ped)
    if not networkId or networkId <= 0 then return nil end
    return networkId
end

local function pedForNetworkId(networkId)
    if type(networkId) ~= 'number' or networkId <= 0
        or not NetworkDoesEntityExistWithNetworkId(networkId) then return nil end
    local ped = NetworkGetEntityFromNetworkId(networkId)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end
    return ped
end

local function cacheRejectedPed(ped, ttl, now, model, networkId)
    if ttl <= 0 then return end
    rejectedPeds[ped] = {
        model = model or unsignedHash(GetEntityModel(ped)),
        network_id = networkId or networkIdFor(ped) or 0,
        retry_at = now + ttl,
    }
end

local function collectCandidates()
    local candidates = {}
    local renewalCandidates = {}
    local discoveryCandidates = {}
    local playerPed = PlayerPedId()
    if playerPed == 0 or not DoesEntityExist(playerPed) then return candidates end
    local playerCoords = GetEntityCoords(playerPed)

    local eligibleCount = 0
    local pool = GetGamePool('CPed')
    local batchSize = math.max(1, tonumber(Config.AmbientScanBatchSize) or 32)
    local radiusSquared = discoveryRadius * discoveryRadius
    local now = GetGameTimer()
    local transientTtl = math.max(0,
        tonumber(Config.AmbientTransientRejectedCacheMs or Config.AmbientRejectedCacheMs) or 3000)
    local stableTtl = math.max(transientTtl,
        tonumber(Config.AmbientStableRejectedCacheMs) or 20000)
    for index, ped in ipairs(pool) do
        local cached = rejectedPeds[ped]
        local exists = DoesEntityExist(ped)
        local model = cached and exists and unsignedHash(GetEntityModel(ped)) or nil
        local cachedNetworkId = cached and exists and (networkIdFor(ped) or 0) or nil
        local rejected = cached and cached.model == model
            and cached.network_id == cachedNetworkId and now < cached.retry_at
        if not rejected and ped ~= playerPed and exists then
            local stableRejected = IsPedAPlayer(ped) or not IsPedHuman(ped)
            local transientRejected = not stableRejected and (IsEntityDead(ped)
                or IsPedFatallyInjured(ped) or IsPedInAnyVehicle(ped, false)
                or not NetworkGetEntityIsNetworked(ped))
            if stableRejected then
                cacheRejectedPed(ped, stableTtl, now, model, cachedNetworkId)
            elseif transientRejected then
                cacheRejectedPed(ped, transientTtl, now, model, cachedNetworkId)
            else
                local coords = GetEntityCoords(ped)
                local dx, dy, dz = playerCoords.x - coords.x, playerCoords.y - coords.y,
                    playerCoords.z - coords.z
                if dx * dx + dy * dy + dz * dz <= radiusSquared then
                    local networkId = networkIdFor(ped)
                    local state = Entity(ped).state
                    local managedNpcId = state.humalike_npc_id
                    local isAmbientRenewal = type(managedNpcId) == 'string'
                        and AmbientPeds[managedNpcId] == ped
                        and type(AmbientNpcEntries[managedNpcId]) == 'table'
                    if networkId and networkId > 0
                        and type(state.humalike_debug_spawn_id) ~= 'string'
                        and (type(managedNpcId) ~= 'string' or isAmbientRenewal) then
                        local candidate = {
                            network_id = networkId,
                            model_hash = model or unsignedHash(GetEntityModel(ped)),
                            x = coords.x,
                            y = coords.y,
                            z = coords.z,
                            heading = GetEntityHeading(ped),
                            zone_code = GetNameOfZone(coords.x, coords.y, coords.z),
                        }
                        if isAmbientRenewal then
                            renewalCandidates[#renewalCandidates + 1] = candidate
                        else
                            eligibleCount = eligibleCount + 1
                            if #discoveryCandidates < Config.AmbientMaxCandidatesPerReport then
                                discoveryCandidates[#discoveryCandidates + 1] = candidate
                            else
                                local replaceAt = math.random(1, eligibleCount)
                                if replaceAt <= Config.AmbientMaxCandidatesPerReport then
                                    discoveryCandidates[replaceAt] = candidate
                                end
                            end
                        end
                    elseif networkId and networkId > 0 then
                        rejectedPeds[ped] = nil
                    else
                        cacheRejectedPed(ped, transientTtl, now, model, networkId)
                    end
                end
            end
        end
        if index % batchSize == 0 and index < #pool then Wait(0) end
    end
    for ped, cached in pairs(rejectedPeds) do
        if now >= cached.retry_at or not DoesEntityExist(ped) then
            rejectedPeds[ped] = nil
        end
    end
    for index = #discoveryCandidates, 2, -1 do
        local other = math.random(1, index)
        discoveryCandidates[index], discoveryCandidates[other] =
            discoveryCandidates[other], discoveryCandidates[index]
    end
    local maxCandidates = Config.AmbientMaxCandidatesPerReport
    for index = 1, math.min(#renewalCandidates, maxCandidates) do
        candidates[#candidates + 1] = renewalCandidates[index]
    end
    for index = 1, math.min(#discoveryCandidates, maxCandidates - #candidates) do
        candidates[#candidates + 1] = discoveryCandidates[index]
    end
    return candidates
end

local function removeAmbientAssignment(npcId)
    local ped = AmbientPeds[npcId]
    local entry = AmbientNpcEntries[npcId]
    if ped then
        rejectedPeds[ped] = nil
        TriggerEvent('humalike:npc:ambientPedRemoved', npcId, ped, entry)
        if DoesEntityExist(ped) and Entity(ped).state.humalike_npc_id == npcId then
            Entity(ped).state:set('humalike_npc_id', nil, false)
        end
    end
    AmbientPeds[npcId] = nil
    AmbientNpcEntries[npcId] = nil
end

local function clearAmbientAssignments()
    local npcIds = {}
    for npcId in pairs(AmbientPeds) do npcIds[#npcIds + 1] = npcId end
    for _, npcId in ipairs(npcIds) do removeAmbientAssignment(npcId) end
end

local function bindAmbientLease(lease)
    local ped = pedForNetworkId(lease.network_id)
    if not ped or GetEntityType(ped) ~= 1 or IsPedAPlayer(ped) then return false end

    local npcId = lease.npc_id
    local previousPed = AmbientPeds[npcId]
    local previousEntry = AmbientNpcEntries[npcId]
    local changed = previousPed ~= ped or not previousEntry
        or previousEntry.entity_id ~= lease.entity_id
        or previousEntry.network_id ~= lease.network_id
        or previousEntry.lease_token ~= lease.lease_token
    if not changed then
        previousEntry.name = lease.display_name
        previousEntry.language = lease.language
        previousEntry.voice_muted = lease.voice_muted == true
        if Entity(ped).state.humalike_npc_id ~= npcId then
            Entity(ped).state:set('humalike_npc_id', npcId, false)
        end
        return true
    end
    if changed and previousPed then removeAmbientAssignment(npcId) end

    AmbientPeds[npcId] = ped
    AmbientNpcEntries[npcId] = {
        name = lease.display_name,
        entity_id = lease.entity_id,
        network_id = lease.network_id,
        routing_bucket = lease.routing_bucket,
        lease_token = lease.lease_token,
        language = lease.language,
        voice_muted = lease.voice_muted == true,
    }
    Entity(ped).state:set('humalike_npc_id', npcId, false)
    if changed then
        TriggerEvent('humalike:npc:ambientPedAssigned', npcId, ped, AmbientNpcEntries[npcId])
    end
    return true
end

local function leaseIsBound(npcId, lease)
    local ped, entry = AmbientPeds[npcId], AmbientNpcEntries[npcId]
    local resolvedPed = pedForNetworkId(lease.network_id)
    return ped and resolvedPed == ped and GetEntityType(ped) == 1
        and not IsPedAPlayer(ped) and entry
        and entry.entity_id == lease.entity_id
        and entry.network_id == lease.network_id
        and entry.lease_token == lease.lease_token
        and entry.routing_bucket == lease.routing_bucket
        and entry.name == lease.display_name
        and entry.language == lease.language
        and entry.voice_muted == (lease.voice_muted == true)
        and Entity(ped).state.humalike_npc_id == npcId
end

RegisterNetEvent('humalike:npc:ambientLeases')
AddEventHandler('humalike:npc:ambientLeases', function(payload)
    ambientEnabled = payload.enabled == true
    discoveryRadius = math.min(
        tonumber(payload.discovery_radius) or Config.AmbientBootstrapRadius,
        Config.AmbientBootstrapRadius)
    if not payload.enabled or type(payload.leases) ~= 'table' then
        desiredAmbientLeases = {}
        clearAmbientAssignments()
        return
    end

    local desired = {}
    for _, lease in ipairs(payload.leases) do
        if type(lease.npc_id) == 'string' and type(lease.network_id) == 'number'
            and type(lease.lease_token) == 'string' then
            desired[lease.npc_id] = lease
        end
    end
    desiredAmbientLeases = desired
    for npcId, lease in pairs(desired) do
        if not leaseIsBound(npcId, lease) then bindAmbientLease(lease) end
    end
    local removed = {}
    for npcId in pairs(AmbientPeds) do
        if not desired[npcId] then removed[#removed + 1] = npcId end
    end
    for _, npcId in ipairs(removed) do removeAmbientAssignment(npcId) end
end)

CreateThread(function()
    while true do
        local unresolved = false
        for npcId, lease in pairs(desiredAmbientLeases) do
            if not leaseIsBound(npcId, lease) then
                unresolved = true
                local ped = AmbientPeds[npcId]
                if ped then removeAmbientAssignment(npcId) end
                bindAmbientLease(lease)
            end
        end
        Wait(unresolved and 500 or 2000)
    end
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('humalike:npc:requestAmbientLeaseSnapshot')
end)

CreateThread(function()
    while true do
        Wait(ambientEnabled == false and 30000 or Config.AmbientScanIntervalMs)
        if HumalikeReportAmbientCandidates ~= nil then
            local ok, err = pcall(function()
                HumalikeReportAmbientCandidates(collectCandidates())
            end)
            if not ok then
                print(('[humalike-npc] ambient scan failed: %s'):format(tostring(err)))
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        desiredAmbientLeases = {}
        rejectedPeds = {}
        clearAmbientAssignments()
    end
end)
