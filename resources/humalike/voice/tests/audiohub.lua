local nuiCallbacks = {}
local nuiMessages = {}
local handlers = {}
local exported = {}
local commands = {}
local printed = {}
local invoking = 'hub_adapter'

Config = { Integrations = { audiohub = 'auto' } }

function RegisterNUICallback(name, callback) nuiCallbacks[name] = callback end
function SendNUIMessage(message) nuiMessages[#nuiMessages + 1] = message end
function AddEventHandler(name, callback) handlers[name] = callback end
function RegisterCommand(name, callback) commands[name] = callback end
function GetCurrentResourceName() return 'humalike' end
function GetInvokingResource() return invoking end
function GetGameTimer() return 1000 end
exports = function(name, callback) exported[name] = callback end
local rawPrint = print
function print(line) printed[#printed + 1] = line end

dofile('../integration/client/provider_registry.lua')
dofile('client/audiohub.lua')

local function attach(id)
    local response
    nuiCallbacks.audiohubAttach({ id = id }, function(value) response = value end)
    return response
end

local function signal(id, payload)
    local response
    nuiCallbacks.audiohubSignal({ id = id, payload = payload }, function(value) response = value end)
    return response
end

local function detach(id)
    local response
    nuiCallbacks.audiohubDetach({ id = id }, function(value) response = value end)
    return response
end

local function lastMessage(kind)
    for index = #nuiMessages, 1, -1 do
        if nuiMessages[index].type == kind then return nuiMessages[index], index end
    end
    return nil
end

-- No adapter at all: the page opens the device itself.
local response = attach('mic-1')
assert(response.ok and response.status == 'none', 'no adapter must answer none')
assert(exported.GetAudioHubStatus().state == 'unavailable')

nuiCallbacks.audiohubAttach({ id = ('x'):rep(65) }, function(value) response = value end)
assert(response.ok == false and response.reason == 'invalid_session')

-- A forced name that is not registered is unavailable, never none.
Config.Integrations.audiohub = 'shared_mic'
response = attach('mic-1')
assert(response.status == 'unavailable' and response.reason == 'unavailable')
Config.Integrations.audiohub = 'auto'

local ok, err = exported.RegisterAudioHub({
    name = 'shared_mic', apiVersion = 1, priority = 100,
    Attach = function() return true end,
    Detach = function() end,
})
assert(not ok and err == 'invalid audio hub adapter', 'descriptor without Signal was accepted')

local hubUp = true
local calls = {}
local adapter = {
    name = 'shared_mic', apiVersion = 1, priority = 100,
    Available = function() return hubUp end,
    Attach = function(id)
        calls[#calls + 1] = { 'attach', id }
        return true
    end,
    Detach = function(id) calls[#calls + 1] = { 'detach', id } end,
    Signal = function(id, payload) calls[#calls + 1] = { 'signal', id, payload } end,
}
local function last() return calls[#calls] or {} end

ok, err = exported.RegisterAudioHub(adapter)
assert(ok, err)
assert(exported.GetAudioHubStatus().state == 'selected')
assert(exported.GetAudioHubStatus().selected.name == 'shared_mic')
assert(lastMessage('audiohub:available'), 'registering an available hub did not notify the page')

-- Registered but not available: unavailable, never none.
hubUp = false
response = attach('mic-1')
assert(response.status == 'unavailable' and response.reason == 'unavailable')
assert(exported.GetAudioHubStatus().state == 'unavailable')
hubUp = true

local availableBefore = select(2, lastMessage('audiohub:available'))
HumalikeVoiceAudioHub.Poll()
local _, availableAfter = lastMessage('audiohub:available')
assert(availableAfter > availableBefore, 'hub coming back did not notify the page')

response = attach('mic-1')
assert(response.status == 'attached')
assert(last()[1] == 'attach' and last()[2] == 'mic-1')
assert(exported.GetAudioHubStatus().sessions == 1)

-- A live id cannot be attached twice.
response = attach('mic-1')
assert(response.ok == false and response.reason == 'already_attached')
assert(#calls == 1, 'refused re-attach reached the adapter')

response = signal('mic-1', { type = 'answer', sdp = 'v=0' })
assert(response.ok and last()[1] == 'signal' and last()[3].sdp == 'v=0')

response = signal('mic-unknown', {})
assert(response.ok == false and response.reason == 'unknown_session')
assert(last()[2] == 'mic-1', 'signal for an unknown session reached the adapter')

-- Delivery is scoped to the resource that owns the session.
assert(exported.AudioHubDeliver('mic-1', 'signal', { type = 'offer', sdp = 'v=0' }))
assert(nuiMessages[#nuiMessages].type == 'audiohub:signal')
assert(nuiMessages[#nuiMessages].id == 'mic-1')
assert(exported.AudioHubDeliver('mic-1', 'state', { capturing = true }))
assert(nuiMessages[#nuiMessages].type == 'audiohub:state')
local delivered, reason = exported.AudioHubDeliver('mic-1', 'level', 0.5)
assert(not delivered and reason == 'invalid_action')
invoking = 'other_resource'
delivered, reason = exported.AudioHubDeliver('mic-1', 'signal', {})
assert(not delivered and reason == 'unknown_session',
    'another resource delivered into a session it does not own')
invoking = 'hub_adapter'

response = detach('mic-1')
assert(response.ok and last()[1] == 'detach' and last()[2] == 'mic-1')
assert(not exported.AudioHubDeliver('mic-1', 'state', {}), 'detached session still accepted delivery')
response = detach('mic-1')
assert(response.ok == false and response.reason == 'unknown_session')

-- Attach refused or failing: unavailable with a reason, no session behind.
adapter.Attach = function() return false end
exported.RegisterAudioHub(adapter)
response = attach('mic-2')
assert(response.status == 'unavailable' and response.reason == 'attach_refused')
assert(not exported.AudioHubDeliver('mic-2', 'state', {}), 'rejected attach left a session')

adapter.Attach = function() error('boom') end
exported.RegisterAudioHub(adapter)
response = attach('mic-2')
assert(response.status == 'unavailable' and response.reason == 'attach_failed')
assert(exported.GetAudioHubStatus().state == 'degraded')

adapter.Attach = function(id)
    calls[#calls + 1] = { 'attach', id }
    return true
end
exported.RegisterAudioHub(adapter)

-- A throwing Signal is a session error for the page and a Detach for the adapter.
adapter.Signal = function() error('hub gone') end
exported.RegisterAudioHub(adapter)
response = attach('mic-3')
assert(response.status == 'attached')
response = signal('mic-3', { type = 'answer', sdp = 'v=0' })
assert(response.ok == false and response.reason == 'signal_failed')
assert(last()[1] == 'detach' and last()[2] == 'mic-3')
assert(printed[#printed]:find('audio hub adapter shared_mic.Signal failed: .*hub gone'), printed[#printed])
assert(exported.GetAudioHubStatus().sessions == 0)
adapter.Signal = function(id, payload) calls[#calls + 1] = { 'signal', id, payload } end
exported.RegisterAudioHub(adapter)

-- Forced 'none' disables the hub even with an adapter registered.
Config.Integrations.audiohub = 'none'
response = attach('mic-3')
assert(response.status == 'none')
assert(exported.GetAudioHubStatus().state == 'disabled')
Config.Integrations.audiohub = 'auto'

-- Forced name selects that adapter regardless of priority.
invoking = 'second_adapter'
ok, err = exported.RegisterAudioHub({
    name = 'other_mic', apiVersion = 1, priority = 1000,
    Attach = function() return true end, Detach = function() end,
    Signal = function() end,
})
assert(ok, err)
invoking = 'hub_adapter'
assert(exported.GetAudioHubStatus().selected.name == 'other_mic')
Config.Integrations.audiohub = 'shared_mic'
assert(exported.GetAudioHubStatus().selected.name == 'shared_mic')
Config.Integrations.audiohub = 'auto'

-- Equal highest priorities are an ambiguity, not a silent choice.
HumalikeAudioHubAdapters.other_mic.priority = 100
assert(exported.GetAudioHubStatus().state == 'ambiguous')
response = attach('mic-3')
assert(response.status == 'unavailable' and response.reason == 'ambiguous')
handlers.onClientResourceStop('second_adapter')
assert(exported.GetAudioHubStatus().state == 'selected')

-- Available() flipping false with an open session fails it towards the page
-- and detaches at the adapter.
response = attach('mic-4')
assert(response.status == 'attached')
hubUp = false
HumalikeVoiceAudioHub.Poll()
local state = lastMessage('audiohub:state')
assert(state.id == 'mic-4' and state.state.capturing == false
    and state.state.error == 'hub-unavailable')
assert(last()[1] == 'detach' and last()[2] == 'mic-4')
assert(exported.GetAudioHubStatus().sessions == 0)
hubUp = true
HumalikeVoiceAudioHub.Poll()

-- A dying adapter resource fails its sessions towards the page without
-- calling into the stopping resource.
response = attach('mic-5')
assert(response.status == 'attached')
local before = #calls
handlers.onClientResourceStop('hub_adapter')
state = lastMessage('audiohub:state')
assert(state.id == 'mic-5' and state.state.error == 'hub-stopped')
assert(#calls == before, 'stop handler called into the stopping resource')
assert(exported.GetAudioHubStatus().state == 'unavailable')
response = attach('mic-6')
assert(response.status == 'none')

-- Reset detaches sessions quietly when the NUI page is replaced.
exported.RegisterAudioHub(adapter)
response = attach('mic-7')
assert(response.status == 'attached')
before = #nuiMessages
HumalikeVoiceAudioHub.Reset()
assert(last()[1] == 'detach' and last()[2] == 'mic-7')
assert(#nuiMessages == before, 'reset notified a page that no longer exists')
assert(not exported.AudioHubDeliver('mic-7', 'state', {}), 'reset left a session')

-- Unregister detaches at the adapter and tells the page.
response = attach('mic-8')
assert(response.status == 'attached')
ok, err = exported.UnregisterAudioHub('shared_mic')
assert(ok, err)
assert(last()[1] == 'detach' and last()[2] == 'mic-8')
state = lastMessage('audiohub:state')
assert(state.id == 'mic-8' and state.state.error == 'hub-stopped')

-- Stopping humalike itself detaches every session at the adapter.
exported.RegisterAudioHub(adapter)
response = attach('mic-9')
assert(response.status == 'attached')
handlers.onClientResourceStop('humalike')
assert(last()[1] == 'detach' and last()[2] == 'mic-9')

-- humalike_status reports the audio hub domain.
commands.humalike_status()
assert(printed[#printed]:find('^%[humalike%] audiohub setting=auto state=selected selected=shared_mic sessions=0$'),
    printed[#printed])

print = rawPrint
print('audiohub: ok')
