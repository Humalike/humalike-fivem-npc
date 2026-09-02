local nuiCallbacks = {}
local nuiMessages = {}
local handlers = {}
local exported = {}
local invoking = 'hub_adapter'

Config = { Integrations = { audiohub = 'auto' } }

function RegisterNUICallback(name, callback) nuiCallbacks[name] = callback end
function SendNUIMessage(message) nuiMessages[#nuiMessages + 1] = message end
function AddEventHandler(name, callback) handlers[name] = callback end
function GetCurrentResourceName() return 'humalike' end
function GetInvokingResource() return invoking end
function GetGameTimer() return 1000 end
exports = function(name, callback) exported[name] = callback end

dofile('client/audiohub.lua')

local function attach(id)
    local response
    nuiCallbacks.audiohubAttach({ id = id, track = true, level = false },
        function(value) response = value end)
    return response
end

-- Without a registered adapter every attach is refused, so the NUI opens the
-- device itself: the pre-adapter behavior.
local response = attach('mic-1')
assert(response.ok and response.available == false)
assert(exported.GetAudioHubStatus().state == 'unavailable')

nuiCallbacks.audiohubAttach({ id = ('x'):rep(65) }, function(value) response = value end)
assert(response.ok == false, 'oversized session id was accepted')

local ok, err = exported.RegisterAudioHub({
    name = 'shared_mic', apiVersion = 1, priority = 100,
    Attach = function() return true end,
    Detach = function() end,
})
assert(not ok and err == 'invalid audio hub adapter', 'descriptor without Signal was accepted')

local calls = {}
local adapter = {
    name = 'shared_mic', apiVersion = 1, priority = 100,
    Attach = function(id, options)
        calls[#calls + 1] = { 'attach', id, options }
        return true
    end,
    Detach = function(id) calls[#calls + 1] = { 'detach', id } end,
    Signal = function(id, payload) calls[#calls + 1] = { 'signal', id, payload } end,
}
ok, err = exported.RegisterAudioHub(adapter)
assert(ok, err)
assert(exported.GetAudioHubStatus().state == 'selected')
assert(exported.GetAudioHubStatus().selected.name == 'shared_mic')

response = attach('mic-1')
assert(response.available == true)
assert(calls[#calls][1] == 'attach' and calls[#calls][2] == 'mic-1')
assert(calls[#calls][3].track == true and calls[#calls][3].level == false)

nuiCallbacks.audiohubSignal({ id = 'mic-1', payload = { type = 'answer', sdp = 'v=0' } },
    function() end)
assert(calls[#calls][1] == 'signal' and calls[#calls][3].sdp == 'v=0')

nuiCallbacks.audiohubSignal({ id = 'mic-unknown', payload = {} }, function() end)
assert(calls[#calls][2] == 'mic-1', 'signal for an unknown session reached the adapter')

-- Delivery is scoped to the resource that owns the session.
assert(exported.AudioHubDeliver('mic-1', 'signal', { type = 'offer', sdp = 'v=0' }))
assert(nuiMessages[#nuiMessages].type == 'audiohub:signal')
assert(nuiMessages[#nuiMessages].id == 'mic-1')
assert(exported.AudioHubDeliver('mic-1', 'state', { capturing = true }))
assert(nuiMessages[#nuiMessages].type == 'audiohub:state')
assert(not exported.AudioHubDeliver('mic-1', 'level', 0.5), 'unknown action was delivered')
invoking = 'other_resource'
assert(not exported.AudioHubDeliver('mic-1', 'signal', {}),
    'another resource delivered into a session it does not own')
invoking = 'hub_adapter'

nuiCallbacks.audiohubDetach({ id = 'mic-1' }, function() end)
assert(calls[#calls][1] == 'detach' and calls[#calls][2] == 'mic-1')
assert(not exported.AudioHubDeliver('mic-1', 'state', {}), 'detached session still accepted delivery')

-- An adapter that rejects or fails an attach leaves no session behind.
adapter.Attach = function() return false end
exported.RegisterAudioHub(adapter)
response = attach('mic-2')
assert(response.available == false)
assert(not exported.AudioHubDeliver('mic-2', 'state', {}), 'rejected attach left a session')

adapter.Attach = function() error('boom') end
exported.RegisterAudioHub(adapter)
response = attach('mic-2')
assert(response.available == false)
assert(exported.GetAudioHubStatus().state == 'degraded')

adapter.Attach = function() return true end
exported.RegisterAudioHub(adapter)

-- Forced 'none' disables the hub even with an adapter registered.
Config.Integrations.audiohub = 'none'
response = attach('mic-3')
assert(response.available == false)
assert(exported.GetAudioHubStatus().state == 'disabled')
Config.Integrations.audiohub = 'auto'

-- Equal highest priorities are an ambiguity, not a silent choice.
invoking = 'second_adapter'
ok, err = exported.RegisterAudioHub({
    name = 'other_mic', apiVersion = 1, priority = 100,
    Attach = function() return true end, Detach = function() end,
    Signal = function() end,
})
assert(ok, err)
invoking = 'hub_adapter'
assert(exported.GetAudioHubStatus().state == 'ambiguous')
response = attach('mic-3')
assert(response.available == false)
handlers.onClientResourceStop('second_adapter')
assert(exported.GetAudioHubStatus().state == 'selected')

-- A dying adapter resource fails its sessions towards the page.
response = attach('mic-4')
assert(response.available == true)
handlers.onClientResourceStop('hub_adapter')
local last = nuiMessages[#nuiMessages]
assert(last.type == 'audiohub:state' and last.id == 'mic-4')
assert(last.state.capturing == false and last.state.error == 'hub-stopped')
assert(exported.GetAudioHubStatus().state == 'unavailable')
response = attach('mic-5')
assert(response.available == false)

-- Reset detaches sessions quietly when the NUI page is replaced.
exported.RegisterAudioHub(adapter)
response = attach('mic-6')
assert(response.available == true)
local before = #nuiMessages
HumalikeVoiceAudioHub.Reset()
assert(calls[#calls][1] == 'detach' and calls[#calls][2] == 'mic-6')
assert(#nuiMessages == before, 'reset notified a page that no longer exists')
assert(not exported.AudioHubDeliver('mic-6', 'state', {}), 'reset left a session')

-- Voluntary unregister behaves like a stop for open sessions.
response = attach('mic-7')
assert(response.available == true)
ok, err = exported.UnregisterAudioHub('shared_mic')
assert(ok, err)
last = nuiMessages[#nuiMessages]
assert(last.type == 'audiohub:state' and last.id == 'mic-7'
    and last.state.error == 'hub-stopped')

-- Stopping humalike itself detaches every session at the adapter.
exported.RegisterAudioHub(adapter)
response = attach('mic-8')
assert(response.available == true)
handlers.onClientResourceStop('humalike')
assert(calls[#calls][1] == 'detach' and calls[#calls][2] == 'mic-8')

print('audiohub: ok')
