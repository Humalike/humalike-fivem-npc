local handlers, timers, requests, statuses = {}, {}, {}, {}
local readyEvents, edgeEvents, voiceEvents, refreshEvents = {}, {}, {}, {}
local persistedLease = nil

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
        edge_node_id = 'edge-a',
        edge_generation = 7,
        voice_url = 'https://voice.example',
        voice_node_id = 'voice-a',
        voice_generation = 4,
        callback_current = {
            token = string.rep('c', 64), valid_from_unix = 50, valid_until_unix = 200,
        },
        callback_next = {
            token = string.rep('n', 64), valid_from_unix = 200, valid_until_unix = 800,
        },
    }
end

local malformed = credentials('boot-1')
malformed.voice_url = nil
assert(HumaLike.ReplaceRuntimeCredentials(malformed, 'boot-1') == false)
local malformedEdge = credentials('boot-1')
malformedEdge.edge_generation = nil
assert(HumaLike.ReplaceRuntimeCredentials(malformedEdge, 'boot-1') == false)
local malformedVoice = credentials('boot-1')
malformedVoice.voice_node_id = nil
assert(HumaLike.ReplaceRuntimeCredentials(malformedVoice, 'boot-1') == false)

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

requests[3].callback(409, { error = { code = 'assignment_not_ready' } })
assert(statuses[#statuses].detail == 'bootstrap failed with HTTP 409 code=assignment_not_ready')
assert(#timers == 4 and timers[4].delay >= 800 and timers[4].delay <= 1200)
timers[4].callback()
assert(#requests == 4)

local bootId = requests[4].payload.boot_id
requests[4].callback(200, credentials(bootId))
assert(statuses[#statuses].phase == 'ready')
assert(HumaLike.RuntimeCredentials().bootId == bootId)
assert(persistedLease == 'lease-1')
assert(HumaLike.RuntimeCredentials().edgeUrl == 'https://edge-a.example')
assert(HumaLike.RuntimeCredentials().edgeNodeId == 'edge-a')
assert(HumaLike.RuntimeCredentials().edgeGeneration == 7)
assert(HumaLike.RuntimeCredentials().voiceNodeId == 'voice-a')
assert(HumaLike.RuntimeCredentials().voiceGeneration == 4)
assert(#timers == 5 and timers[5].delay >= 8000 and timers[5].delay <= 12000)
assert(#readyEvents == 1)

timers[5].callback()
assert(requests[5].action == 'renew_fivem_runtime')
assert(requests[5].targetUrl == nil,
    'renewal discovery must continue to use the stable endpoint')
local renewed = credentials(bootId)
renewed.edge_access_token = string.rep('f', 64)
renewed.voice_access_token = string.rep('w', 64)
requests[5].callback(200, renewed)
assert(#edgeEvents == 0 and #voiceEvents == 0,
    'token renewal for the same assignments must not reconnect either plane')

timers[6].callback()
local moved = credentials(bootId)
moved.edge_url = 'https://edge-b.example'
moved.edge_node_id = 'edge-b'
moved.edge_generation = 8
requests[6].callback(200, moved)
assert(#readyEvents == 1 and #edgeEvents == 1 and #voiceEvents == 0)
assert(HumaLike.RuntimeCredentials().edgeNodeId == 'edge-b')
assert(HumaLike.RuntimeCredentials().edgeGeneration == 8)

timers[7].callback()
local voiceMoved = moved
voiceMoved.voice_url = 'https://voice-b.example'
voiceMoved.voice_node_id = 'voice-b'
voiceMoved.voice_generation = 5
requests[7].callback(200, voiceMoved)
assert(#edgeEvents == 1 and #voiceEvents == 1)
assert(#refreshEvents == 0, 'periodic assignment changes are plane-specific')

local credentialsVisibleDuringStop = false
AddEventHandler('humalike:core:stopping', function()
    credentialsVisibleDuringStop = HumaLike.RuntimeCredentials() ~= nil
end)
TriggerEvent('onResourceStop', 'humalike')
assert(credentialsVisibleDuringStop)
assert(HumaLike.RuntimeCredentials() == nil)

print('core_runtime: ok')
