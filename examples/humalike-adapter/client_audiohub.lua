-- Optional: shared-microphone (audio hub) adapter. Connects the HumaLike voice
-- NUI to a resource that owns the client's only microphone capture and relays
-- the track over a loopback RTCPeerConnection. Replace HUB_RESOURCE and the
-- event names with your hub's protocol; delete the file if you have no hub.
-- Contract: resources/humalike/INTEGRATIONS.md, "Client audio hub".

local HUB_RESOURCE = 'my-audiohub'
local resource = GetCurrentResourceName()
local attached = {}

local function hubRunning()
    return GetResourceState(HUB_RESOURCE) == 'started'
end

local function registerAudioHub()
    exports.humalike:RegisterAudioHub({
        name = 'my_audiohub',
        apiVersion = 1,
        priority = 100,
        Available = hubRunning,
        Attach = function(id)
            if not hubRunning() then return false end
            attached[id] = true
            TriggerEvent('my-audiohub:attach', { resource = resource, id = id })
            return true
        end,
        Detach = function(id)
            attached[id] = nil
            TriggerEvent('my-audiohub:detach', { resource = resource, id = id })
        end,
        Signal = function(id, payload)
            TriggerEvent('my-audiohub:signal', {
                resource = resource, id = id, payload = payload,
            })
        end,
    })
end

-- Hub -> HumaLike: `action` is 'signal' (a WebRTC blob) or 'state'.
AddEventHandler('my-audiohub:deliver', function(target, action, id, data)
    if target ~= resource then return end
    exports.humalike:AudioHubDeliver(id, action, data)
end)

-- HumaLike sees this adapter stop, not the hub behind it: fail the sessions
-- the hub was serving so voice waits for it instead of timing out.
AddEventHandler('onClientResourceStop', function(stopped)
    if stopped ~= HUB_RESOURCE then return end
    for id in pairs(attached) do
        exports.humalike:AudioHubDeliver(id, 'state', { capturing = false, error = 'hub-stopped' })
    end
    attached = {}
end)

AddEventHandler('onClientResourceStart', function(started)
    if started == resource then registerAudioHub() end
end)

AddEventHandler('humalike:integration:ready', registerAudioHub)
