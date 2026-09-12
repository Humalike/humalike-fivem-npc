local handlers, timers, requests, statuses = {}, {}, {}, {}
local readyEvents, edgeEvents, voiceEvents, refreshEvents = {}, {}, {}, {}
local persistedLease = nil
local output = {}
local consolePrint = print

print = function(message)
    output[#output + 1] = tostring(message)
end

GetConvar = function(name)
    if name == 'humalike_license_key' then return 'ak_' .. string.rep('x', 40) end
    return ''
end
GetCurrentResourceName = function() return 'humalike' end
GetGameTimer = function() return 7 end
GetResourceKvpString = function() return persistedLease end
SetResourceKvp = function(_, value) persistedLease = value end
os.time = function() return 100 end
SetTimeout = function(delay, callback)
    timers[#timers + 1] = { delay = delay, callback = callback }
end
AddEventHandler = function(name, callback)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = callback
end
TriggerEvent = function(name, payload)
    for _, callback in ipairs(handlers[name] or {}) do callback(payload) end
end

HumaLike = {
    SetStatus = function(phase, detail)
        statuses[#statuses + 1] = { phase = phase, detail = detail }
    end,
    ErrorCode = function(body)
        return body and body.error and body.error.code or nil
    end,
    EdgeRequest = function(action, token, payload, callback, targetUrl)
        requests[#requests + 1] = {
            action = action, token = token, payload = payload, callback = callback,
            targetUrl = targetUrl,
        }
    end,
}

dofile('../server/core/retries.lua')
dofile('../server/core/credentials.lua')
dofile('../server/core/bootstrap.lua')
AddEventHandler('humalike:core:ready', function(payload)
    readyEvents[#readyEvents + 1] = payload
end)
AddEventHandler('humalike:runtime:edgeChanged', function(payload)
    edgeEvents[#edgeEvents + 1] = payload
end)
AddEventHandler('humalike:runtime:voiceChanged', function(payload)
    voiceEvents[#voiceEvents + 1] = payload
end)
AddEventHandler('humalike:runtime:refreshed', function(payload)
    refreshEvents[#refreshEvents + 1] = payload
end)

assert(HumaLike.RetryDelay(1, 0) == 200)
assert(HumaLike.RetryDelay(99, 1) == 2400)
assert(HumaLike.RenewalDelay(0) == 8000)
assert(HumaLike.RenewalDelay(1) == 12000)

local function credentials(bootId)
    return {
        server_id = 'server-1',
        boot_id = bootId,
        lease_id = 'lease-1',
        edge_access_token = string.rep('e', 64),
        voice_access_token = string.rep('v', 64),
        access_tokens_expire_at = '2030-01-01T00:00:00Z',
        edge_url = 'https://edge-a.example',
        edge_assignment_id = '11111111-1111-4111-8111-111111111111',
        edge_node_id = 'edge-a',
        edge_boot_id = '22222222-2222-4222-8222-222222222222',
        edge_generation = 7,
        voice_url = 'https://voice.example',
        voice_assignment_id = '33333333-3333-4333-8333-333333333333',
        voice_node_id = 'voice-a',
        voice_boot_id = '44444444-4444-4444-8444-444444444444',
        voice_generation = 4,
        callback_current = {
            token = string.rep('c', 64), valid_from_unix = 50, valid_until_unix = 200,
        },
        callback_next = {
            token = string.rep('n', 64), valid_from_unix = 200, valid_until_unix = 800,
        },
    }
end

for _, field in ipairs({
    'edge_assignment_id',
    'edge_node_id',
    'edge_boot_id',
    'edge_generation',
    'voice_assignment_id',
    'voice_node_id',
    'voice_boot_id',
    'voice_generation',
}) do
    local incomplete = credentials('boot-1')
    incomplete[field] = nil
    assert(HumaLike.ReplaceRuntimeCredentials(incomplete, 'boot-1') == false,
        ('runtime credentials without %s must fail closed'):format(field))
end

local malformed = credentials('boot-1')
malformed.voice_url = nil
assert(HumaLike.ReplaceRuntimeCredentials(malformed, 'boot-1') == false)
local insecureVoice = credentials('boot-1')
insecureVoice.voice_url = 'http://voice.example'
assert(HumaLike.ReplaceRuntimeCredentials(insecureVoice, 'boot-1') == false,
    'runtime credentials must reject an insecure public voice URL')
local insecureEdge = credentials('boot-1')
insecureEdge.edge_url = 'http://edge.example'
assert(HumaLike.ReplaceRuntimeCredentials(insecureEdge, 'boot-1') == false,
    'runtime credentials must reject an insecure assigned edge URL')
local malformedEdge = credentials('boot-1')
malformedEdge.edge_generation = nil
assert(HumaLike.ReplaceRuntimeCredentials(malformedEdge, 'boot-1') == false)
local malformedVoice = credentials('boot-1')
malformedVoice.voice_node_id = nil
assert(HumaLike.ReplaceRuntimeCredentials(malformedVoice, 'boot-1') == false)
local unassignedEdge = credentials('boot-1')
unassignedEdge.edge_node_id = nil
unassignedEdge.edge_generation = nil
assert(HumaLike.ReplaceRuntimeCredentials(unassignedEdge, 'boot-1') == false)
local unassignedVoice = credentials('boot-1')
unassignedVoice.voice_node_id = nil
unassignedVoice.voice_generation = nil
assert(HumaLike.ReplaceRuntimeCredentials(unassignedVoice, 'boot-1') == false)
local malformedEdgeNode = credentials('boot-1')
malformedEdgeNode.edge_node_id = 'edge node'
assert(HumaLike.ReplaceRuntimeCredentials(malformedEdgeNode, 'boot-1') == false)
local malformedVoiceGeneration = credentials('boot-1')
malformedVoiceGeneration.voice_generation = 4.5
assert(HumaLike.ReplaceRuntimeCredentials(malformedVoiceGeneration, 'boot-1') == false)
local malformedAssignmentId = credentials('boot-1')
malformedAssignmentId.edge_assignment_id = 'not-a-uuid'
assert(HumaLike.ReplaceRuntimeCredentials(malformedAssignmentId, 'boot-1') == false)
local malformedNodeBootId = credentials('boot-1')
malformedNodeBootId.voice_boot_id = 'not-a-uuid'
assert(HumaLike.ReplaceRuntimeCredentials(malformedNodeBootId, 'boot-1') == false)

TriggerEvent('onResourceStart', 'humalike')
assert(#timers == 1 and timers[1].delay == 0)
timers[1].callback()
assert(#requests == 1 and requests[1].action == 'bootstrap_fivem_runtime')
assert(requests[1].payload.previous_lease_id == nil)
assert(HumaLike.RequestBootstrap('duplicate', 1, true) == false)
assert(HumaLike.RequestBootstrap('duplicate', 1, true) == false)
requests[1].callback(401, { error = { code = 'UNAUTHORIZED' } })
assert(statuses[#statuses].phase == 'unauthorized')
assert(#timers == 1, 'an invalid license must not retry every two seconds')
assert(HumaLike.RequestBootstrap('edge restart', 1, true) == true)
assert(#timers == 2 and timers[2].delay == 0)
timers[2].callback()
requests[2].callback(401, { error = { code = 'RUNTIME_LEASE_UNKNOWN' } })
assert(#timers == 3 and timers[3].delay >= 400 and timers[3].delay <= 600)
timers[3].callback()
assert(#requests == 3)

requests[3].callback(409, { error = { code = 'EDGE_ASSIGNMENT_NOT_READY' } })
assert(statuses[#statuses].detail == 'runtime assignment is not ready')
assert(#timers == 4 and timers[4].delay >= 800 and timers[4].delay <= 1200)
timers[4].callback()
assert(#requests == 4)

local bootId = requests[4].payload.boot_id
local incompleteBootstrap = credentials(bootId)
local rejectedSecret = 'sensitive-' .. string.rep('z', 64)
incompleteBootstrap.edge_access_token = rejectedSecret
incompleteBootstrap.edge_assignment_id = nil
requests[4].callback(200, incompleteBootstrap)
assert(statuses[#statuses].phase == 'degraded')
assert(statuses[#statuses].detail == 'bootstrap returned malformed credentials')
assert(HumaLike.RuntimeCredentials() == nil)
assert(#readyEvents == 0)
assert(not table.concat(output, '\n'):find(rejectedSecret, 1, true),
    'a rejected control-plane response must not expose credentials in logs')
assert(#timers == 5 and timers[5].delay >= 1600 and timers[5].delay <= 2400)
timers[5].callback()
assert(#requests == 5)

requests[5].callback(200, credentials(bootId))
assert(statuses[#statuses].phase == 'ready')
assert(HumaLike.RuntimeCredentials().bootId == bootId)
assert(persistedLease == 'lease-1')
assert(HumaLike.RuntimeCredentials().edgeUrl == 'https://edge-a.example')
assert(HumaLike.RuntimeCredentials().edgeAssignmentId ==
    '11111111-1111-4111-8111-111111111111')
assert(HumaLike.RuntimeCredentials().edgeNodeId == 'edge-a')
assert(HumaLike.RuntimeCredentials().edgeBootId ==
    '22222222-2222-4222-8222-222222222222')
assert(HumaLike.RuntimeCredentials().edgeGeneration == 7)
local initialEdgeKey = HumaLike.EdgeAssignmentKey()
assert(type(initialEdgeKey) == 'string' and initialEdgeKey ~= '')
assert(HumaLike.IsCurrentEdgeAssignment(initialEdgeKey))
assert(HumaLike.RuntimeCredentials().voiceAssignmentId ==
    '33333333-3333-4333-8333-333333333333')
assert(HumaLike.RuntimeCredentials().voiceNodeId == 'voice-a')
assert(HumaLike.RuntimeCredentials().voiceBootId ==
    '44444444-4444-4444-8444-444444444444')
assert(HumaLike.RuntimeCredentials().voiceGeneration == 4)
local initialVoiceKey = HumaLike.VoiceAssignmentKey()
assert(type(initialVoiceKey) == 'string' and initialVoiceKey ~= '')
assert(HumaLike.IsCurrentVoiceAssignment(initialVoiceKey))
assert(#timers == 6 and timers[6].delay >= 8000 and timers[6].delay <= 12000)
assert(#readyEvents == 1)

timers[6].callback()
assert(requests[6].action == 'renew_fivem_runtime')
assert(requests[6].targetUrl == nil,
    'renewal discovery must continue to use the stable endpoint')
local renewed = credentials(bootId)
renewed.edge_access_token = string.rep('f', 64)
renewed.voice_access_token = string.rep('w', 64)
requests[6].callback(200, renewed)
assert(#edgeEvents == 0 and #voiceEvents == 0,
    'token renewal for the same assignments must not reconnect either plane')

timers[7].callback()
local moved = credentials(bootId)
moved.edge_url = 'https://edge-b.example'
moved.edge_assignment_id = '55555555-5555-4555-8555-555555555555'
moved.edge_node_id = 'edge-b'
moved.edge_boot_id = '66666666-6666-4666-8666-666666666666'
moved.edge_generation = 8
requests[7].callback(200, moved)
assert(#readyEvents == 1 and #edgeEvents == 1 and #voiceEvents == 0)
assert(HumaLike.RuntimeCredentials().edgeNodeId == 'edge-b')
assert(HumaLike.RuntimeCredentials().edgeGeneration == 8)
assert(not HumaLike.IsCurrentEdgeAssignment(initialEdgeKey),
    'edge assignment identity must change with its generation')
assert(edgeEvents[1].assignmentId == moved.edge_assignment_id)
assert(edgeEvents[1].bootId == moved.edge_boot_id)

timers[8].callback()
local voiceMoved = moved
voiceMoved.voice_url = 'https://voice-b.example'
voiceMoved.voice_assignment_id = '77777777-7777-4777-8777-777777777777'
voiceMoved.voice_node_id = 'voice-b'
voiceMoved.voice_boot_id = '88888888-8888-4888-8888-888888888888'
voiceMoved.voice_generation = 5
requests[8].callback(200, voiceMoved)
assert(#edgeEvents == 1 and #voiceEvents == 1)
assert(not HumaLike.IsCurrentVoiceAssignment(initialVoiceKey),
    'voice assignment identity must change with its generation')
assert(#refreshEvents == 0, 'periodic assignment changes are plane-specific')

timers[9].callback()
local unassignedRenewal = credentials(bootId)
unassignedRenewal.voice_node_id = nil
unassignedRenewal.voice_generation = nil
requests[9].callback(200, unassignedRenewal)
assert(HumaLike.RuntimeCredentials() == nil,
    'an unassigned renewal must invalidate active runtime credentials')
assert(statuses[#statuses].phase == 'bootstrapping')
assert(statuses[#statuses].detail == 'renewal returned malformed credentials')
assert(#timers == 10 and timers[10].delay == 0)
timers[10].callback()
assert(requests[10].action == 'bootstrap_fivem_runtime')
requests[10].callback(200, voiceMoved)
assert(HumaLike.RuntimeCredentials().voiceNodeId == 'voice-b')

assert(HumaLike.RequestBootstrap('manual assignment refresh', 1, true) == true)
assert(#timers == 12 and timers[12].delay == 0)
timers[12].callback()
local malformedRefresh = credentials(bootId)
malformedRefresh.edge_node_id = nil
malformedRefresh.edge_generation = nil
requests[11].callback(200, malformedRefresh)
assert(HumaLike.RuntimeCredentials() == nil,
    'a malformed bootstrap refresh must invalidate active credentials')
assert(statuses[#statuses].phase == 'degraded')
assert(#timers == 13 and timers[13].delay >= 400 and timers[13].delay <= 600)
local requestCount = #requests
timers[11].callback()
assert(#requests == requestCount, 'invalidation must fence the previous renewal timer')
timers[13].callback()
local reassigned = credentials(bootId)
reassigned.edge_url = 'https://edge-c.example'
reassigned.edge_assignment_id = '99999999-9999-4999-8999-999999999999'
reassigned.edge_node_id = 'edge-c'
reassigned.edge_boot_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
reassigned.edge_generation = 9
reassigned.voice_url = 'https://voice-c.example'
reassigned.voice_assignment_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
reassigned.voice_node_id = 'voice-c'
reassigned.voice_boot_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
reassigned.voice_generation = 6
requests[12].callback(200, reassigned)
assert(#edgeEvents == 2 and edgeEvents[2].nodeId == 'edge-c')
assert(#voiceEvents == 2 and voiceEvents[2].nodeId == 'voice-c')

local refreshCountBeforeRejectedRenewal = #refreshEvents
timers[14].callback()
assert(requests[13].action == 'renew_fivem_runtime')
HumaLike.InvalidateRuntimeCredentials()
requests[13].callback(200, credentials(bootId))
assert(HumaLike.RuntimeCredentials() == nil,
    'an in-flight renewal must not restore invalidated credentials')
assert(#timers == 14, 'an invalidated renewal must not schedule another timer')
assert(HumaLike.RequestBootstrap('rejected edge request', 1, true) == true)
assert(#timers == 15 and timers[15].delay == 0)
timers[15].callback()
requests[14].callback(200, reassigned)
assert(#refreshEvents == refreshCountBeforeRejectedRenewal + 1,
    'bootstrap after edge rejection must notify runtime consumers')

timers[16].callback()
assert(requests[15].action == 'renew_fivem_runtime')
requests[15].callback(409, { error = { code = 'VOICE_ASSIGNMENT_NOT_READY' } })
assert(HumaLike.RuntimeCredentials() == nil,
    'an unavailable voice assignment must invalidate active credentials')
assert(statuses[#statuses].phase == 'bootstrapping')
assert(#timers == 17 and timers[17].delay == 0)
timers[17].callback()
requests[16].callback(200, reassigned)
assert(HumaLike.RuntimeCredentials() ~= nil)

timers[18].callback()
requests[17].callback(401, { error = { code = 'UNAUTHORIZED' } })
assert(HumaLike.RuntimeCredentials() == nil,
    'a rejected renewal must invalidate active runtime credentials')
assert(#timers == 19 and timers[19].delay == 0)
timers[19].callback()
requests[18].callback(200, reassigned)
assert(HumaLike.RuntimeCredentials() ~= nil)

local credentialsVisibleDuringStop = false
AddEventHandler('humalike:core:stopping', function()
    credentialsVisibleDuringStop = HumaLike.RuntimeCredentials() ~= nil
end)
TriggerEvent('onResourceStop', 'humalike')
assert(credentialsVisibleDuringStop)
assert(HumaLike.RuntimeCredentials() == nil)

consolePrint('core_runtime: ok')
