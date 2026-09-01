
local downed = {} -- npcId -> state
local lastRequestAt = {} -- source -> ms

local function config()
    return Config.Wounded or {}
end

local function enabled()
    return config().Enabled ~= false
end
local function rollDeceased()
    local chance = tonumber(config().DeathChancePercent) or 0
    if chance <= 0 then return false end
    return math.random(1, 100) <= chance
end
local function pinBody(entityId, pinned)
    if type(entityId) ~= 'number' or entityId <= 0 then return end
    if type(SetEntityOrphanMode) ~= 'function' or not DoesEntityExist(entityId) then return end
    -- KeepEntity prevents the population manager deleting an unattended body.
    SetEntityOrphanMode(entityId, pinned and 2 or 0)
end
local function resolveNetworkId(entityId, entityHandle)
    local lease = HumalikeResolveAmbientLease
        and HumalikeResolveAmbientLease(entityId)
        or AmbientNpcLeases and AmbientNpcLeases[entityHandle] or nil
    local leased = lease and tonumber(lease.network_id or lease.entity_id) or nil
    if leased and leased > 0 then return leased end
    if type(entityHandle) ~= 'number' or entityHandle <= 0 then return nil end
    if type(NetworkGetNetworkIdFromEntity) ~= 'function'
        or not DoesEntityExist(entityHandle) then return nil end
    local networkId = NetworkGetNetworkIdFromEntity(entityHandle)
    return networkId and networkId > 0 and networkId or nil
end

local function broadcast(npcId, state)
    TriggerClientEvent('humalike:npc:npcDownedState', -1, npcId, {
        state = state.state,
        entity_id = state.entity_id,
        network_id = state.network_id,
        expires_in_ms = state.state == 'wounded'
            and math.max(0, state.expires_at - GetGameTimer()) or nil,
    })
end
local function bleedOut(npcId)
    local state = downed[npcId]
    if not state then return end
    state.state = 'deceased'
    state.expires_at = nil
    state.deceased_at = GetGameTimer()
    HumalikeDebug('npc %s bled out; wiping memory, body left to be collected', npcId)
    broadcast(npcId, state)
    TriggerEvent('humalike:npc:npcDeceased', npcId, state.entity_id, 'bled_out')
end
local lastMedicalDispatch = nil
local function requestMedicalDispatch(npcId, entity, deceased)
    local dispatch = config().Dispatch or {}
    if dispatch.Enabled == false or not HumalikeDispatch.Available() then return end
    if type(entity) ~= 'number' or not DoesEntityExist(entity) then return end
    local now = GetGameTimer()
    local throttle = (tonumber(dispatch.ThrottleSeconds) or 0) * 1000
    if lastMedicalDispatch and now - lastMedicalDispatch < throttle then return end
    if math.random(1, 100) > (tonumber(dispatch.Chance) or 100) then
        HumalikeDebug('npc %s downing went unreported to EMS', npcId)
        return
    end
    lastMedicalDispatch = now
    local coords = GetEntityCoords(entity)
    SetTimeout(tonumber(dispatch.DelayMs) or 0, function()
        HumalikeDispatch.Report('npc_medical', {
            coords = { x = coords.x, y = coords.y, z = coords.z },
            status = deceased and 'deceased' or 'wounded',
            npcId = npcId,
        })
    end)
end
local function notifyBodyCollected(npcId, coords)
    local dispatch = config().Dispatch or {}
    if dispatch.Enabled == false or dispatch.NotifyMortuary == false
        or not HumalikeDispatch.Available() then return end
    if coords == nil then return end
    HumalikeDispatch.Report('npc_medical', {
        coords = { x = coords.x, y = coords.y, z = coords.z },
        status = 'collected',
        npcId = npcId,
    })
end
local function resolveBody(state)
    local entity
    if HumalikeResolveAmbientEntity then
        entity = HumalikeResolveAmbientEntity(state.entity_id)
    end
    if type(entity) ~= 'number' or entity <= 0 or not DoesEntityExist(entity) then
        entity = state.entity_handle
    end
    if entity then state.entity_handle = entity end
    return entity
end

local function finalize(npcId, reason)
    local state = downed[npcId]
    if not state then return end
    downed[npcId] = nil
    pinBody(resolveBody(state), false)
    if HumalikeForgetReportedDeath then HumalikeForgetReportedDeath(state.entity_id) end
    TriggerClientEvent('humalike:npc:npcDownedState', -1, npcId, { state = 'gone' })
    HumalikeDebug('npc %s deceased (%s); wiping memory', npcId, reason)
    TriggerEvent('humalike:npc:npcDeceased', npcId, state.entity_id, reason)
end
function HumalikeWoundedOnLethalHit(npcId, entityId, entityHandle)
    if not enabled() or downed[npcId] then return end
    if not entityHandle then
        if HumalikeResolveAmbientEntity then
            entityHandle = HumalikeResolveAmbientEntity(entityId)
        else
            entityHandle = entityId
        end
    end
    -- Roll once server-side so witnesses cannot disagree.
    local deceased = rollDeceased()
    downed[npcId] = {
        state = deceased and 'deceased' or 'wounded',
        entity_id = entityId,
        entity_handle = entityHandle,
        network_id = resolveNetworkId(entityId, entityHandle),
        started_at = GetGameTimer(),
        expires_at = GetGameTimer() + (tonumber(config().DurationMs) or 300000),
        deceased_at = deceased and GetGameTimer() or nil,
    }
    pinBody(entityHandle, true)
    requestMedicalDispatch(npcId, entityHandle, deceased)
    if ForgetNpcPose then ForgetNpcPose(npcId) end
    HumalikeDebug('npc %s %s', npcId, deceased and 'killed outright' or 'wounded')
    broadcast(npcId, downed[npcId])
    TriggerEvent(deceased and 'humalike:npc:npcDeceased' or 'humalike:npc:npcWounded',
        npcId, entityId, 'damage')
end

function HumalikeWoundedStateOf(npcId)
    local state = downed[npcId]
    return state and state.state or nil
end
local function withinReach(source, state)
    local entity = resolveBody(state)
    if type(entity) ~= 'number' or entity <= 0 or not DoesEntityExist(entity) then
        return true
    end
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local reach = tonumber(config().TreatmentDistance) or 6.0
    return #(GetEntityCoords(ped) - GetEntityCoords(entity)) <= reach
end
local function permitted(source, npcId)
    local state = downed[npcId]
    if not state then return false end
    local jobs = state.state == 'wounded' and config().MedicJobs or nil
    if state.state == 'deceased' then
        jobs = {}
        for _, job in ipairs(config().MedicJobs or {}) do jobs[#jobs + 1] = job end
        for _, job in ipairs(config().PoliceJobs or {}) do jobs[#jobs + 1] = job end
    end
    local allowed = HumalikePlayer.HasJob(
        source, jobs or {}, config().RequireDuty == true)
    HumalikeDebug('job gate: npc %s state=%s jobs=[%s] duty=%s -> allowed=%s',
        npcId, state.state, table.concat(jobs or {}, ','),
        tostring(config().RequireDuty), tostring(allowed))
    return allowed
end
local function throttled(source, lane)
    local key = tostring(source) .. ':' .. (lane or 'treat')
    local now = GetGameTimer()
    if now - (lastRequestAt[key] or -10000) < 1000 then return true end
    lastRequestAt[key] = now
    return false
end
RegisterNetEvent('humalike:npc:finishNpcTreatment')
AddEventHandler('humalike:npc:finishNpcTreatment', function(npcId, intent)
    local source = source
    if not enabled() or throttled(source) then return end
    local state = downed[npcId]
    if not state or type(intent) ~= 'string' then return end
    if intent ~= (state.state == 'wounded' and 'revive' or 'mortuary') then return end
    if not withinReach(source, state) then
        HumalikeDebug('npc %s treatment refused for %s (too far from the body)', npcId, tostring(source))
        return
    end
    if not permitted(source, npcId) then
        HumalikeDebug('npc %s treatment refused for %s (job gate)', npcId, tostring(source))
        return
    end
    if state.state == 'wounded' then
        downed[npcId] = nil
        pinBody(resolveBody(state), false)
        TriggerClientEvent('humalike:npc:npcDownedState', -1, npcId, {
            state = 'revived',
            entity_id = state.entity_id,
            linger_ms = tonumber(config().LingerAfterReviveMs) or 30000,
            linger_radius = tonumber(config().LingerRadius) or 20.0,
        })
        HumalikeDebug('npc %s revived by %s', npcId, tostring(source))
        local lease = HumalikeResolveAmbientLease
            and HumalikeResolveAmbientLease(state.entity_id)
            or AmbientNpcLeases and AmbientNpcLeases[state.entity_handle] or nil
        TriggerEvent('humalike:npc:npcRevived', source, npcId, state.entity_id,
            lease and lease.lease_token or nil)
        TriggerEvent('humalike:npc:npcHealed', npcId, state.entity_id, source)
    else
        local coords = nil
        local entity = resolveBody(state)
        if type(entity) == 'number' and entity > 0 and DoesEntityExist(entity) then
            coords = GetEntityCoords(entity)
        end
        finalize(npcId, 'mortuary')
        notifyBodyCollected(npcId, coords)
    end
end)
function HumalikeWoundedSweep()
    if not enabled() then return end
    local now = GetGameTimer()
    local expired = {}
    for npcId, state in pairs(downed) do
        if state.state == 'wounded' and now >= state.expires_at then
            expired[#expired + 1] = npcId
        end
    end
    for _, npcId in ipairs(expired) do bleedOut(npcId) end
    local retention = tonumber(config().DeceasedRetentionMs) or 900000
    local unclaimed = {}
    for npcId, state in pairs(downed) do
        if state.state == 'deceased' and state.deceased_at
            and now - state.deceased_at >= retention then
            unclaimed[#unclaimed + 1] = npcId
        end
    end
    for _, npcId in ipairs(unclaimed) do finalize(npcId, 'unclaimed') end
end

CreateThread(function()
    while true do
        Wait(1000)
        HumalikeWoundedSweep()
    end
end)

AddEventHandler('playerDropped', function()
    local prefix = tostring(source) .. ':'
    for key in pairs(lastRequestAt) do
        if key:sub(1, #prefix) == prefix then lastRequestAt[key] = nil end
    end
end)
RegisterNetEvent('humalike:npc:requestTreatmentRoles')
AddEventHandler('humalike:npc:requestTreatmentRoles', function()
    local source = source
    if not enabled() or throttled(source, 'roles') then return end
    local function holds(jobs)
        return HumalikePlayer.HasJob(
            source, jobs or {}, config().RequireDuty == true)
    end
    TriggerClientEvent('humalike:npc:treatmentRoles', source, {
        medic = holds(config().MedicJobs),
        police = holds(config().PoliceJobs),
    })
end)
RegisterNetEvent('humalike:npc:requestDownedStates')
AddEventHandler('humalike:npc:requestDownedStates', function()
    local source = source
    if not enabled() or throttled(source, 'snapshot') then return end
    for npcId, state in pairs(downed) do
        TriggerClientEvent('humalike:npc:npcDownedState', source, npcId, {
            state = state.state,
            entity_id = state.entity_id,
            network_id = state.network_id,
            expires_in_ms = state.state == 'wounded'
                and math.max(0, state.expires_at - GetGameTimer()) or nil,
        })
    end
end)
