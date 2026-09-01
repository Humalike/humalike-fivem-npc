local function randomHex(length)
    local value = ''
    for _ = 1, length do value = value .. ('%x'):format(math.random(0, 15)) end
    return value
end

local function uuid()
    return randomHex(8) .. '-' .. randomHex(4) .. '-4' .. randomHex(3)
        .. '-8' .. randomHex(3) .. '-' .. randomHex(12)
end

HumalikeWorldCabins = {
    vehicleRecords = {},
    playerMembers = {},
    stateRevision = 0,
    publishRevision = 0,
    publishedDigest = nil,
    inFlight = nil,
    lastAttemptAt = 0,
    lastSuccessAt = nil,
    lastStatus = nil,
    lastError = nil,
    sentSnapshots = 0,
}

local function publicCabin(cabin)
    if not cabin then return nil end
    return {
        id = cabin.id,
        networkId = cabin.networkId,
        seat = cabin.seat,
        dimension = cabin.dimension,
    }
end

local function validInteger(value, minimum, maximum)
    return type(value) == 'number' and value % 1 == 0
        and value >= minimum and value <= maximum
end

local function memberDigest(includeSessions)
    local parts = {}
    for playerId, cabin in pairs(HumalikeWorldCabins.playerMembers) do
        local sessionId = includeSessions and HumalikeWorldVoice
            and HumalikeWorldVoice.SessionId(playerId) or ''
        parts[#parts + 1] = ('p|%s|%s|%s|%s|%s|%s'):format(playerId, sessionId or '',
            cabin.id, cabin.networkId, cabin.seat, cabin.dimension)
    end
    table.sort(parts)
    return table.concat(parts, ';')
end

local function notifyClient(playerId)
    TriggerClientEvent('humalike:world:cabinMembership', playerId, {
        v = 1,
        epoch = HumalikeWorldAuthority.epoch,
        revision = HumalikeWorldCabins.stateRevision,
        membership = publicCabin(HumalikeWorldCabins.playerMembers[playerId]),
    })
end

local function removeMember(playerId)
    local previous = HumalikeWorldCabins.playerMembers[playerId]
    if not previous then return false end
    HumalikeWorldCabins.playerMembers[playerId] = nil
    local key = ('%s:%s'):format(previous.dimension, previous.networkId)
    local record = HumalikeWorldCabins.vehicleRecords[key]
    if record then
        record.members = record.members - 1
        if record.members <= 0 then HumalikeWorldCabins.vehicleRecords[key] = nil end
    end
    return true
end

local function setMember(playerId, vehicle)
    local authority = HumalikeWorldAuthority.players[playerId]
    local accepted = WorldConfig.cabins.enabled and authority and authority.loaded ~= false
        and type(vehicle) == 'table'
        and validInteger(vehicle.networkId, 1, 0xffffffff)
        and validInteger(vehicle.seat, -1, 31)
    local dimension = accepted and (tonumber(authority.routingBucket) or 0) or nil
    local previous = HumalikeWorldCabins.playerMembers[playerId]
    if previous and accepted and previous.networkId == vehicle.networkId
        and previous.seat == vehicle.seat and previous.dimension == dimension then return false end
    local changed = removeMember(playerId)
    if accepted then
        local key = ('%s:%s'):format(dimension, vehicle.networkId)
        local record = HumalikeWorldCabins.vehicleRecords[key]
        if not record then
            record = { id = uuid(), members = 0 }
            HumalikeWorldCabins.vehicleRecords[key] = record
        end
        record.members = record.members + 1
        HumalikeWorldCabins.playerMembers[playerId] = {
            id = record.id,
            networkId = vehicle.networkId,
            seat = vehicle.seat,
            dimension = dimension,
        }
        changed = true
    end
    if changed then
        HumalikeWorldCabins.stateRevision = HumalikeWorldCabins.stateRevision + 1
        HumalikeWorldDebug('cabin registry changed revision=%s',
            HumalikeWorldCabins.stateRevision)
    end
    notifyClient(playerId)
    return changed
end

function HumalikeWorldCabins.BuildSnapshot(empty)
    local credentials = HumaLike.RuntimeCredentials()
    local members = {}
    if not empty then
        for playerId, cabin in pairs(HumalikeWorldCabins.playerMembers) do
            local sessionId = HumalikeWorldVoice and HumalikeWorldVoice.SessionId(playerId)
            if sessionId then
                members[#members + 1] = {
                    kind = 'player',
                    id = tostring(playerId),
                    sessionId = sessionId,
                    cabin = publicCabin(cabin),
                }
            end
        end
    end
    table.sort(members, function(left, right) return left.id < right.id end)
    while #members > 4096 do members[#members] = nil end
    return {
        serverId = credentials and credentials.serverId or '',
        epoch = HumalikeWorldAuthority.epoch,
        revision = HumalikeWorldCabins.publishRevision,
        members = members,
    }
end

local function send(requestState)
    if not WorldConfig.voice.enabled or not HumaLike.RuntimeCredentials() then
        HumalikeWorldCabins.lastError = 'voice disabled or runtime unavailable'
        return false
    end
    HumalikeWorldCabins.lastAttemptAt = GetGameTimer()
    HumaLike.PostVoice('/v1/fivem/cabins', requestState.body, function(status)
        if HumalikeWorldCabins.inFlight ~= requestState then return end
        status = tonumber(status) or 0
        HumalikeWorldCabins.lastStatus = status
        if status >= 200 and status < 300 then
            HumalikeWorldCabins.publishedDigest = requestState.digest
            HumalikeWorldCabins.inFlight = nil
            HumalikeWorldCabins.lastSuccessAt = os.time()
            HumalikeWorldCabins.lastError = nil
            HumalikeWorldCabins.sentSnapshots = HumalikeWorldCabins.sentSnapshots + 1
            HumalikeWorldCabins.Publish(false, not WorldConfig.cabins.enabled)
        else
            HumalikeWorldCabins.lastError = 'HTTP ' .. tostring(status)
        end
    end)
    return true
end

function HumalikeWorldCabins.Publish(force, empty)
    local now = GetGameTimer()
    if HumalikeWorldCabins.inFlight then
        if now - HumalikeWorldCabins.lastAttemptAt >= WorldConfig.cabins.retryIntervalMs then
            send(HumalikeWorldCabins.inFlight)
        end
        return false
    end
    local digest = empty and '__empty__' or memberDigest(true)
    if not force and digest == HumalikeWorldCabins.publishedDigest then return false end
    HumalikeWorldCabins.publishRevision = HumalikeWorldCabins.publishRevision + 1
    local body = HumalikeWorldCabins.BuildSnapshot(empty)
    body.revision = HumalikeWorldCabins.publishRevision
    local requestState = { digest = digest, body = body }
    HumalikeWorldCabins.inFlight = requestState
    return send(requestState)
end

function HumalikeWorldCabins.Status()
    local playerCount, vehicleCount = 0, 0
    for _ in pairs(HumalikeWorldCabins.playerMembers) do playerCount = playerCount + 1 end
    for _ in pairs(HumalikeWorldCabins.vehicleRecords) do vehicleCount = vehicleCount + 1 end
    return {
        enabled = WorldConfig.cabins.enabled,
        stateRevision = HumalikeWorldCabins.stateRevision,
        publishRevision = HumalikeWorldCabins.publishRevision,
        playerCount = playerCount,
        npcCount = 0,
        vehicleCount = vehicleCount,
        inFlight = HumalikeWorldCabins.inFlight ~= nil,
        lastStatus = HumalikeWorldCabins.lastStatus,
        lastSuccessAt = HumalikeWorldCabins.lastSuccessAt,
        lastError = HumalikeWorldCabins.lastError,
        sentSnapshots = HumalikeWorldCabins.sentSnapshots,
    }
end

RegisterNetEvent('humalike:world:cabinState', function(vehicle)
    local playerId = tonumber(source)
    if not playerId then return end
    if setMember(playerId, vehicle) then
        HumalikeWorldCabins.Publish(false, not WorldConfig.cabins.enabled)
    end
end)

AddEventHandler('humalike:world:authorityChanged', function(delta)
    local playerId = tonumber(delta.playerId)
    if not playerId then return end
    local previous = HumalikeWorldCabins.playerMembers[playerId]
    if delta.kind == 'remove' then
        if removeMember(playerId) then
            HumalikeWorldCabins.stateRevision = HumalikeWorldCabins.stateRevision + 1
            HumalikeWorldCabins.Publish(false, not WorldConfig.cabins.enabled)
        end
        return
    end
    if previous and setMember(playerId, previous) then
        HumalikeWorldCabins.Publish(false, not WorldConfig.cabins.enabled)
    elseif WorldConfig.cabins.enabled then
        TriggerClientEvent('humalike:world:requestCabinState', playerId)
    end
end)

CreateThread(function()
    Wait(WorldConfig.cabins.startDelayMs)
    local lastRepair = GetGameTimer()
    HumalikeWorldCabins.Publish(true, not WorldConfig.cabins.enabled)
    while true do
        Wait(WorldConfig.cabins.retryIntervalMs)
        local now = GetGameTimer()
        local repair = now - lastRepair >= WorldConfig.cabins.snapshotIntervalMs
        if HumalikeWorldCabins.inFlight or repair then
            HumalikeWorldCabins.Publish(repair, not WorldConfig.cabins.enabled)
        end
        if repair then lastRepair = now end
    end
end)

AddEventHandler('humalike:core:stopping', function()
    HumalikeWorldCabins.inFlight = nil
    HumalikeWorldCabins.Publish(true, true)
end)

AddEventHandler('humalike:core:ready', function()
    HumalikeWorldCabins.inFlight = nil
    HumalikeWorldCabins.Publish(true, not WorldConfig.cabins.enabled)
end)
