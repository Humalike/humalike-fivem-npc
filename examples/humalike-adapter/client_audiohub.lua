--[[
    Optional: shared-microphone (audio hub) adapter.

    If your server runs a resource that owns the only microphone capture on
    the client and relays the live track to consumer NUI frames over a
    loopback RTCPeerConnection, this file connects the HumaLike voice NUI to
    it. Replace HUB_RESOURCE and the event names with your hub's protocol.

    Without such a resource this file is harmless: the adapter reports
    unavailable and HumaLike opens its own capture, exactly as it would
    without an adapter. See resources/humalike/INTEGRATIONS.md.
]]

local HUB_RESOURCE = 'my-audiohub'
local resource = GetCurrentResourceName()

local function hubRunning()
    return GetResourceState(HUB_RESOURCE) == 'started'
end

local function registerAudioHub()
    exports.humalike:RegisterAudioHub({
        name = 'my_audiohub',
        apiVersion = 1,
        priority = 100,
        Available = hubRunning,
        Attach = function(id, options)
            -- options = { track = boolean, level = boolean }. Return false to
            -- refuse; HumaLike then falls back to its own capture.
            TriggerEvent('my-audiohub:attach', {
                resource = resource, id = id,
                track = options.track, level = options.level,
            })
        end,
        Detach = function(id)
            TriggerEvent('my-audiohub:detach', { resource = resource, id = id })
        end,
        Signal = function(id, payload)
            -- payload is an opaque WebRTC offer/answer/ICE blob. Only the
            -- negotiation crosses these events; audio never does.
            TriggerEvent('my-audiohub:signal', {
                resource = resource, id = id, payload = payload,
            })
        end,
    })
end

-- Hub -> HumaLike. Adjust to your hub's delivery protocol; `action` must be
-- 'signal' (a WebRTC blob) or 'state' (for example { capturing = false,
-- error = 'device-busy' }). HumaLike only accepts ids it attached through
-- this resource.
AddEventHandler('my-audiohub:deliver', function(target, action, id, data)
    if target ~= resource then return end
    exports.humalike:AudioHubDeliver(id, action, data)
end)

-- HumaLike notices when this adapter resource stops, but it cannot see the
-- hub resource behind it. Tell it when the hub dies so open sessions fall
-- back immediately instead of waiting out a timeout.
AddEventHandler('onClientResourceStop', function(stopped)
    if stopped ~= HUB_RESOURCE then return end
    -- If your hub tracks sessions itself it may already have delivered a
    -- terminal state; delivering for an unknown id is a harmless no-op.
end)

AddEventHandler('onClientResourceStart', function(started)
    if started == GetCurrentResourceName() then registerAudioHub() end
end)

AddEventHandler('humalike:integration:ready', registerAudioHub)
