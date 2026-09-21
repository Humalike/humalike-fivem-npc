local handlers, timers, requests, statuses, stoppedResources, output = {}, {}, {}, {}, {}, {}
local consolePrint = print

GetConvar = function(name)
    if name == 'humalike_license_key' then return 'ak_' .. string.rep('x', 40) end
    return ''
end
GetCurrentResourceName = function() return 'humalike' end
GetGameTimer = function() return 7 end
GetResourceKvpString = function() return nil end
SetResourceKvp = function() end
StopResource = function(resource) stoppedResources[#stoppedResources + 1] = resource end
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
print = function(message) output[#output + 1] = tostring(message) end

HumaLike = {
    SetStatus = function(phase, detail)
        statuses[#statuses + 1] = { phase = phase, detail = detail }
    end,
    ErrorCode = function(body)
        return body and body.error and body.error.code or nil
    end,
    EdgeRequest = function(action, token, payload, callback)
        requests[#requests + 1] = {
            action = action,
            token = token,
            payload = payload,
            callback = callback,
        }
    end,
}

dofile('../server/core/retries.lua')
dofile('../server/core/credentials.lua')
dofile('../server/core/bootstrap.lua')

TriggerEvent('onResourceStart', 'humalike')
assert(#timers == 1 and timers[1].delay == 0)
timers[1].callback()
assert(#requests == 1 and requests[1].action == 'bootstrap_fivem_runtime')

local rejectedSecret = 'sensitive-' .. string.rep('z', 64)
requests[1].callback(200, {
    server_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    boot_id = requests[1].payload.boot_id,
    lease_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    edge_access_token = rejectedSecret,
    voice_access_token = rejectedSecret,
    access_tokens_expire_at = '2030-01-01T00:00:00Z',
    edge_url = 'https://edge.example',
    edge_assignment_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    edge_node_id = 'edge-1',
    edge_boot_id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    edge_generation = 1,
    voice_url = 'https://voice.example',
    voice_assignment_id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    voice_node_id = 'voice-1',
    voice_boot_id = nil,
    voice_generation = 1,
    callback_current = {
        token = string.rep('c', 64), valid_from_unix = 50, valid_until_unix = 200,
    },
    callback_next = {
        token = string.rep('n', 64), valid_from_unix = 200, valid_until_unix = 800,
    },
})

assert(HumaLike.RuntimeCredentials() == nil)
assert(statuses[#statuses].phase == 'stopped')
assert(#stoppedResources == 1 and stoppedResources[1] == 'humalike')
assert(#timers == 1, 'a failed startup gate must not leave a retry loop running')
assert(not table.concat(output, '\n'):find(rejectedSecret, 1, true),
    'a failed startup gate must not expose credentials in logs')

consolePrint('core_startup_gate: ok')
