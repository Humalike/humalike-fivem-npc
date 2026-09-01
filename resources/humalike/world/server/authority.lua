local function randomHex(length)
    local value = ''
    for _ = 1, length do value = value .. ('%x'):format(math.random(0, 15)) end
    return value
end

local function uuid()
    return randomHex(8) .. '-' .. randomHex(4) .. '-4' .. randomHex(3)
        .. '-8' .. randomHex(3) .. '-' .. randomHex(12)
end

HumalikeWorldAuthority = {
    epoch = uuid(),
    revision = 0,
    players = {},
}

local function currentBucket(playerId)
    return GetPlayerRoutingBucket(tostring(playerId))
end

local function emit(kind, playerId, state)
    HumalikeWorldAuthority.revision = HumalikeWorldAuthority.revision + 1
    TriggerEvent('humalike:world:authorityChanged', {
        v = 1,
        kind = kind,
        epoch = HumalikeWorldAuthority.epoch,
        revision = HumalikeWorldAuthority.revision,
        playerId = tostring(playerId),
        state = HumalikeWorldServerContracts.Copy(state),
    })
end

function HumalikeWorldAuthority.SetIdentity(playerId, value)
    playerId = tonumber(playerId)
    local identity, reason = HumalikeWorldServerContracts.Identity(value)
    if not playerId or playerId <= 0 or not identity then return false, reason end
    local previous = HumalikeWorldAuthority.players[playerId]
    if previous and previous.characterId == identity.characterId
        and previous.name == identity.name
        and json.encode(previous.metadata) == json.encode(identity.metadata)
        and previous.routingBucket == currentBucket(playerId) then return true end
    local generation = previous and previous.generation + 1 or 1
    local state = {
        generation = generation,
        characterId = identity.characterId,
        name = identity.name,
        routingBucket = currentBucket(playerId),
        loaded = true,
        dead = false,
        deafened = false,
        metadata = identity.metadata,
    }
    HumalikeWorldAuthority.players[playerId] = state
    emit('upsert', playerId, state)
    return true
end

function HumalikeWorldAuthority.Patch(playerId, patch)
    playerId = tonumber(playerId)
    local state = playerId and HumalikeWorldAuthority.players[playerId]
    if not state or type(patch) ~= 'table' then return false end
    local changed = false
    for _, key in ipairs({ 'loaded', 'dead', 'deafened' }) do
        if type(patch[key]) == 'boolean' and state[key] ~= patch[key] then
            state[key] = patch[key]
            changed = true
        end
    end
    if patch.metadata ~= nil and json.encode(state.metadata) ~= json.encode(patch.metadata) then
        state.metadata = HumalikeWorldServerContracts.Copy(patch.metadata)
        changed = true
    end
    if not changed then return true end
    state.generation = state.generation + 1
    emit('upsert', playerId, state)
    return true
end

function HumalikeWorldAuthority.Remove(playerId)
    playerId = tonumber(playerId)
    if not playerId or not HumalikeWorldAuthority.players[playerId] then return false end
    HumalikeWorldAuthority.players[playerId] = nil
    emit('remove', playerId, nil)
    return true
end

function HumalikeWorldAuthority.Snapshot()
    HumalikeWorldAuthority.revision = HumalikeWorldAuthority.revision + 1
    return {
        v = 1,
        kind = 'snapshot',
        epoch = HumalikeWorldAuthority.epoch,
        revision = HumalikeWorldAuthority.revision,
        players = HumalikeWorldServerContracts.Copy(HumalikeWorldAuthority.players),
    }
end

AddEventHandler('onPlayerBucketChange', function(player, bucket)
    local playerId, key = tonumber(player), tostring(player)
    SetTimeout(0, function()
        local state = playerId and HumalikeWorldAuthority.players[playerId]
        if not state then return end
        state.routingBucket = tonumber(bucket) or currentBucket(key)
        state.generation = state.generation + 1
        emit('upsert', playerId, state)
    end)
end)

AddEventHandler('playerDropped', function() HumalikeWorldAuthority.Remove(source) end)
