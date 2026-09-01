local unarmed = GetHashKey('WEAPON_UNARMED') % 4294967296

local function ambientLease(entityId)
    if HumalikeResolveAmbientLease then return HumalikeResolveAmbientLease(entityId) end
    local lease = AmbientNpcLeases and AmbientNpcLeases[entityId] or nil
    return lease, lease and entityId or nil
end

local function normalize(hash)
    return hash % 4294967296
end

local function validHash(hash)
    return type(hash) == 'number'
        and hash == math.floor(hash)
        and hash >= -2147483648
        and hash <= 4294967295
end

local function validName(hash, name)
    return type(name) == 'string'
        and name:match('^WEAPON_[A-Z0-9_]+$') ~= nil
        and normalize(GetHashKey(name)) == hash
end

local function validTransition(eventType, previousWeapon, weapon)
    if eventType == 'weapon_drawn' then
        return previousWeapon == unarmed and weapon ~= unarmed
    end
    if eventType == 'weapon_holstered' then
        return previousWeapon ~= unarmed and weapon == unarmed
    end
    return false
end

local function post(observation, delay, attempt)
    attempt = attempt or 1
    HumalikeHttp.PostAction('ingest_world_event', observation, function(ok, status, body)
        if ok and body and body.ok == true then return end
        if attempt < 5 and (status == 0 or status >= 500) then
            SetTimeout(delay, function() post(observation, delay * 2, attempt + 1) end)
        end
    end)
end

local function validTarget(playerId, npcId, entityId)
    if type(npcId) ~= 'string' then return false end
    if NpcRegistry[npcId] then return entityId == nil, nil end
    local lease, entity = ambientLease(entityId)
    local valid = type(entityId) == 'number' and entityId > 0 and entityId % 1 == 0
        and entity and GetEntityRoutingBucket(entity) == GetPlayerRoutingBucket(playerId)
        and lease and lease.npc_id == npcId and type(lease.lease_token) == 'string'
    return valid, valid and lease.lease_token or nil
end

local aimingStates = {}

RegisterNetEvent('humalike:npc:aimingCandidateChanged')
AddEventHandler('humalike:npc:aimingCandidateChanged', function(npcId, entityId)
    local playerId = tonumber(source)
    if not playerId or playerId <= 0 or playerId % 1 ~= 0
        or not HumalikePlayer.IsCharacterLoaded(playerId)
        or npcId ~= nil and not validTarget(playerId, npcId, entityId) then return end

    local state = aimingStates[playerId] or { generation = 0 }
    aimingStates[playerId] = state
    if state.candidate == npcId then return end
    state.candidate = npcId
    state.entityId = entityId
    state.generation = state.generation + 1
    local generation = state.generation

    SetTimeout(npcId and 150 or 250, function()
        if state.generation ~= generation or state.candidate ~= npcId
            or not HumalikePlayer.IsCharacterLoaded(playerId)
            or npcId and not validTarget(playerId, npcId, state.entityId) then return end
        local valid, leaseToken = true, nil
        if npcId then valid, leaseToken = validTarget(playerId, npcId, state.entityId) end
        if not valid then return end
        local previous = state.current
        if previous and previous.npc_id == npcId
            and previous.lease_token == leaseToken then return end
        state.current = npcId and { npc_id = npcId, lease_token = leaseToken } or nil

        if previous then
            post({
                fivem_session_id = playerId,
                source_event_id = HumalikeHttp.NextSourceEventId(playerId),
                occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                event = {
                    type = 'aiming_stopped',
                    npc_id = previous.npc_id,
                    lease_token = previous.lease_token,
                },
            }, 1000)
        end
        if npcId then
            post({
                fivem_session_id = playerId,
                source_event_id = HumalikeHttp.NextSourceEventId(playerId),
                occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                event = {
                    type = 'aiming_started',
                    npc_id = npcId,
                    lease_token = leaseToken,
                },
            }, 1000)
        end
    end)
end)

RegisterNetEvent('humalike:npc:weaponStateChanged')
AddEventHandler('humalike:npc:weaponStateChanged', function(eventType, previousWeaponHash,
        weaponHash, previousWeaponName, weaponName)
    local playerId = source
    if not validHash(previousWeaponHash) or not validHash(weaponHash) then return end

    local previousWeapon = normalize(previousWeaponHash)
    local weapon = normalize(weaponHash)
    if not validTransition(eventType, previousWeapon, weapon)
        or not validName(previousWeapon, previousWeaponName)
        or not validName(weapon, weaponName) then return end

    local observation = {
        fivem_session_id = playerId,
        source_event_id = HumalikeHttp.NextSourceEventId(playerId),
        occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        event = { type = eventType },
    }
    if eventType == 'weapon_drawn' then
        observation.event.weapon = weaponName
    else
        observation.event.weapon = previousWeaponName
    end
    post(observation, 1000)
end)

RegisterNetEvent('humalike:npc:npcAttacked')
AddEventHandler('humalike:npc:npcAttacked', function(npcId, entityId, weaponHash, damage,
        weaponName)
    local playerId = source
    local validPlayer = type(playerId) == 'number' and playerId > 0 and playerId % 1 == 0
    local staticNpc = type(npcId) == 'string' and NpcRegistry[npcId] ~= nil
    local lease, entity = ambientLease(entityId)
    local ambientNpc = validPlayer and type(entityId) == 'number' and entityId > 0
        and entityId % 1 == 0 and entity
        and GetEntityRoutingBucket(entity) == GetPlayerRoutingBucket(playerId)
        and lease and lease.npc_id == npcId and type(lease.lease_token) == 'string'
    if not validPlayer
        or type(npcId) ~= 'string' or not staticNpc and not ambientNpc
        or not HumalikePlayer.IsCharacterLoaded(playerId)
        or not validHash(weaponHash)
        or type(damage) ~= 'number' or damage < 0
        or damage ~= damage or damage == math.huge then
        return
    end

    local normalizedHash = normalize(weaponHash)
    local playerPed = GetPlayerPed(playerId)
    if not playerPed or playerPed == 0 or not DoesEntityExist(playerPed)
        or normalize(GetSelectedPedWeapon(playerPed)) ~= normalizedHash then return end
    if not validName(normalizedHash, weaponName) then return end

    post({
        fivem_session_id = playerId,
        source_event_id = HumalikeHttp.NextSourceEventId(playerId),
        occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        event = {
            type = 'attacked_npc',
            npc_id = npcId,
            lease_token = ambientNpc and lease.lease_token or nil,
            weapon = weaponName,
            damage = damage,
        },
    }, 1000)
end)
local reportedDeaths = {}
function HumalikeForgetReportedDeath(entityId)
    if type(entityId) == 'number' then reportedDeaths[entityId] = nil end
end

RegisterNetEvent('humalike:npc:npcDied')
AddEventHandler('humalike:npc:npcDied', function(npcId, entityId)
    local playerId = tonumber(source)
    if not playerId or playerId <= 0 or playerId % 1 ~= 0
        or type(entityId) ~= 'number' or entityId <= 0 or entityId % 1 ~= 0
        or type(npcId) ~= 'string' or not HumalikePlayer.IsCharacterLoaded(playerId) then
        return
    end

    local lease, entity = ambientLease(entityId)
    if not lease or lease.npc_id ~= npcId or type(lease.lease_token) ~= 'string'
        or not entity or GetEntityRoutingBucket(entity) ~= GetPlayerRoutingBucket(playerId)
        or GetEntityHealth(entity) > 0 or reportedDeaths[entityId] then return end
    reportedDeaths[entityId] = true
    if HumalikeWoundedOnLethalHit then
        HumalikeWoundedOnLethalHit(npcId, entityId, entity)
    end

    post({
        fivem_session_id = playerId,
        source_event_id = HumalikeHttp.NextSourceEventId(playerId),
        occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        event = {
            type = 'npc_died',
            npc_id = npcId,
            lease_token = lease.lease_token,
            fatal = HumalikeWoundedStateOf ~= nil
                and HumalikeWoundedStateOf(npcId) == 'deceased' or false,
        },
    }, 1000)
end)
function HumalikeReportNpcWounds(playerId, npcId, entityId, leaseToken, wounds)
    post({
        fivem_session_id = playerId,
        source_event_id = HumalikeHttp.NextSourceEventId(playerId),
        occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        event = {
            type = 'npc_wounded',
            npc_id = npcId,
            lease_token = leaseToken,
            wounds = wounds,
        },
    }, 1000)
end

AddEventHandler('humalike:npc:npcRevived', function(playerId, npcId, entityId, leaseToken)
    playerId = tonumber(playerId)
    if not playerId or playerId <= 0 or playerId % 1 ~= 0
        or type(entityId) ~= 'number' or entityId <= 0 or entityId % 1 ~= 0
        or type(npcId) ~= 'string' or not HumalikePlayer.IsCharacterLoaded(playerId) then
        return
    end

    local lease = ambientLease(entityId)
    if not lease or lease.npc_id ~= npcId or lease.lease_token ~= leaseToken then return end
    reportedDeaths[entityId] = nil
    post({
        fivem_session_id = playerId,
        source_event_id = HumalikeHttp.NextSourceEventId(playerId),
        occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        event = {
            type = 'npc_revived',
            npc_id = npcId,
            lease_token = leaseToken,
        },
    }, 1000)
end)

RegisterNetEvent('humalike:npc:gunshotFired')
local lastGunshotAt = {}
AddEventHandler('humalike:npc:gunshotFired', function()
    local playerId = source
    if type(playerId) ~= 'number' or playerId <= 0 or playerId % 1 ~= 0
        or not HumalikePlayer.IsCharacterLoaded(playerId) then return end

    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end

    local now = GetGameTimer()
    local last = lastGunshotAt[playerId]
    if last and now >= last and now - last < 25 then return end
    lastGunshotAt[playerId] = now

    post({
        fivem_session_id = playerId,
        source_event_id = HumalikeHttp.NextSourceEventId(playerId),
        occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        event = { type = 'gunshot_fired' },
    }, 1000)
end)

AddEventHandler('explosionEvent', function(playerId, explosion)
    playerId = tonumber(playerId)
    if type(playerId) ~= 'number' or playerId <= 0 or playerId % 1 ~= 0
        or type(explosion) ~= 'table'
        or type(explosion.explosionType) ~= 'number' or explosion.explosionType < 0
        or explosion.explosionType % 1 ~= 0
        or type(explosion.posX) ~= 'number' or type(explosion.posY) ~= 'number'
        or type(explosion.posZ) ~= 'number'
        or not HumalikePlayer.IsCharacterLoaded(playerId) then
        return
    end

    post({
        fivem_session_id = playerId,
        source_event_id = HumalikeHttp.NextSourceEventId(playerId),
        occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        event = {
            type = 'explosion_occurred',
            explosion_type = explosion.explosionType,
            x = explosion.posX,
            y = explosion.posY,
            z = explosion.posZ,
        },
    }, 1000)
end)

AddEventHandler('playerDropped', function()
    lastGunshotAt[source] = nil
    local playerId = tonumber(source)
    local aiming = aimingStates[playerId]
    if aiming then aiming.generation = aiming.generation + 1 end
    aimingStates[playerId] = nil
end)
