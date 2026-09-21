local handlers, clientEvents, requests = {}, {}, {}
local now = 5000

WorldConfig = {
    voice = { enabled = true },
    cabins = { enabled = true, retryIntervalMs = 2000,
        snapshotIntervalMs = 30000, startDelayMs = 1000 },
}
HumalikeWorldAuthority = { epoch = 'epoch-1', players = {
    [7] = { loaded = true, routingBucket = 3 },
    [8] = { loaded = true, routingBucket = 3 },
} }
HumalikeWorldVoice = { SessionId = function(playerId) return 'session-' .. playerId end }
HumalikeWorldDebug = function() end
RegisterNetEvent = function(name, callback) handlers[name] = callback end
AddEventHandler = function(name, callback) handlers[name] = callback end
TriggerClientEvent = function(name, target, body)
    clientEvents[#clientEvents + 1] = { name = name, target = target, body = body }
end
GetGameTimer = function() return now end
PerformHttpRequest = function(url, callback, method, body, headers)
    requests[#requests + 1] = { url = url, callback = callback, method = method,
        body = body, headers = headers }
end
json = { encode = function() return '{}' end }
os.time = function() return 123 end
CreateThread = function() end
Wait = function() end
GetCurrentResourceName = function() return 'humalike' end
HumaLike = {
    RuntimeCredentials = function() return { serverId = 'server-1' } end,
    PostVoice = function(path, body, callback)
        requests[#requests + 1] = { url = 'https://voice.example' .. path,
            callback = callback, method = 'POST', body = body }
    end,
}

dofile('server/cabins.lua')
assert(HumalikeWorldCabins.Scan == nil)

source = 7
handlers['humalike:world:cabinState']({ networkId = 501, seat = -1 })
local first = HumalikeWorldCabins.playerMembers[7]
assert(first and first.networkId == 501 and first.seat == -1 and first.dimension == 3)
assert(#clientEvents == 1 and clientEvents[1].body.membership.id == first.id)
assert(#requests == 1 and requests[1].url:match('/v1/fivem/cabins$'))
requests[1].callback(204)

handlers['humalike:world:cabinState']({ networkId = 501, seat = -1 })
assert(#clientEvents == 1 and #requests == 1)

source = 8
handlers['humalike:world:cabinState']({ networkId = 501, seat = 0 })
assert(HumalikeWorldCabins.playerMembers[8].id == first.id)
assert(HumalikeWorldCabins.Status().playerCount == 2)
requests[2].callback(204)

local snapshot = HumalikeWorldCabins.BuildSnapshot(false)
assert(#snapshot.members == 2)
assert(snapshot.members[1].id == '7' and snapshot.members[1].sessionId == 'session-7')

source = 7
handlers['humalike:world:cabinState']({ networkId = 501, seat = -2 })
assert(HumalikeWorldCabins.playerMembers[7] == nil)
assert(clientEvents[#clientEvents].body.membership == nil)
requests[3].callback(204)

handlers['humalike:world:authorityChanged']({ kind = 'remove', playerId = '8' })
assert(next(HumalikeWorldCabins.playerMembers) == nil)
assert(next(HumalikeWorldCabins.vehicleRecords) == nil)
requests[4].callback(204)

WorldConfig.cabins.enabled = false
source = 7
handlers['humalike:world:cabinState']({ networkId = 999, seat = -1 })
assert(HumalikeWorldCabins.playerMembers[7] == nil)

WorldConfig.cabins.enabled = true
handlers['humalike:world:cabinState']({ networkId = 502, seat = -1 })
local oldVoiceRequest = requests[#requests]
local successesBeforeMove = HumalikeWorldCabins.sentSnapshots
handlers['humalike:runtime:voiceChanged']()
local newVoiceRequest = requests[#requests]
assert(newVoiceRequest ~= oldVoiceRequest,
    'voice assignment change must publish the cabin snapshot to the new node')
oldVoiceRequest.callback(204)
assert(HumalikeWorldCabins.sentSnapshots == successesBeforeMove,
    'an old voice-node callback must not mark current cabin state as published')
newVoiceRequest.callback(204)
assert(HumalikeWorldCabins.sentSnapshots == successesBeforeMove + 1,
    'the new voice-node callback must publish current cabin state')

source = 7
handlers['humalike:world:cabinState']({ networkId = 503, seat = -1 })
local abandonedSameAssignmentCabin = requests[#requests]
local successesBeforeRecovery = HumalikeWorldCabins.sentSnapshots
handlers['humalike:runtime:refreshed']({ voiceChanged = false })
local recoveredSameAssignmentCabin = requests[#requests]
assert(recoveredSameAssignmentCabin ~= abandonedSameAssignmentCabin,
    'same-assignment credential recovery must replay cabin state')
abandonedSameAssignmentCabin.callback(204)
assert(HumalikeWorldCabins.sentSnapshots == successesBeforeRecovery,
    'an abandoned cabin callback must remain fenced after credential recovery')
recoveredSameAssignmentCabin.callback(204)
assert(HumalikeWorldCabins.sentSnapshots == successesBeforeRecovery + 1)

local beforeStop = #requests
handlers['humalike:core:stopping']()
assert(#requests == beforeStop + 1)
assert(HumalikeWorldCabins.inFlight.body.members[1] == nil)
print('server_cabins: ok')
