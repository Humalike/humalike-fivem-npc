local nuiCallbacks = {}
local handlers = {}
local commands = {}
local serverEvents = {}
local nuiMessages = {}

function RegisterNUICallback(name, callback) nuiCallbacks[name] = callback end
function RegisterCommand(name, callback) commands[name] = callback end
function RegisterKeyMapping() end
function RegisterNetEvent(name, callback)
    if callback then handlers[name] = callback end
end
function AddEventHandler(name, callback) handlers[name] = callback end
local threads = {}
function CreateThread(callback) threads[#threads + 1] = callback end
function SetTimeout() end
function TriggerServerEvent(name, ...)
    serverEvents[#serverEvents + 1] = { name = name, args = { ... } }
end
function SendNUIMessage(message) nuiMessages[#nuiMessages + 1] = message end
function SetNuiFocus() end
function GetControlInstructionalButton() return 't_PTT' end
function GetHashKey() return 0x1234 end
function GetPlayerServerId() return 7 end
function PlayerId() return 0 end
exports = setmetatable({
    ['humalike'] = {
        GetLocalPlayerState = function() return { seq = 1 } end,
        GetListenerState = function() return { position = { x = 1 }, forward = { x = 0 } } end,
        GetCabinMembership = function() return { vehicle = 'veh-1' } end,
    },
}, { __call = function() end })

local collectorSubscribers = {}
HumalikeWorldCollector = {
    Subscribe = function(kind, callback) collectorSubscribers[kind] = callback end,
}
HumalikeVoicePtt = {}
HumalikeUiLanguage = function() return 'en' end
local directTargetsAvailable
HumalikeNpcDirectTargets = {
    Subscribe = function(callback) callback({ 'npc-1' }) end,
    SetAvailable = function(value) directTargetsAvailable = value end,
    Lock = function() end,
    Unlock = function() end,
}

dofile('client/busy.lua')
assert(loadfile('client/main.lua'))()
assert(type(nuiCallbacks.ready) == 'function')
assert(type(handlers['humalike:world:registrationRequested']) == 'function')
assert(type(handlers['humalike:world:voiceReconnect']) == 'function')
collectorSubscribers.listener({ position = { x = 2 }, forward = { x = 1 } })
assert(nuiMessages[#nuiMessages].type == 'game:listener'
    and nuiMessages[#nuiMessages].position.x == 2, 'the listener goes straight to the NUI')
collectorSubscribers.motion({ seq = 2 })
assert(nuiMessages[#nuiMessages].type == 'game:realtime', 'and so does player motion')

assert(nuiCallbacks.diagnostic == nil)
assert(nuiCallbacks.cabinDiagnostic == nil)

handlers['humalike:world:registrationRequested']()
assert(#serverEvents == 0, 'session requested before NUI ready')

nuiCallbacks.ready({}, function(response) assert(not response.ok) end)
assert(#serverEvents == 0, 'session requested for an invalid NUI boot ID')

nuiCallbacks.ready({ bootId = 'boot-a' }, function(response) assert(response.ok) end)
assert(#serverEvents == 1)
assert(directTargetsAvailable == false, 'new NUI boot did not fail-close direct target readiness')
assert(serverEvents[1].name == 'humalike:world:requestVoiceSession')

nuiCallbacks.ready({ bootId = 'boot-a' }, function(response) assert(response.ok) end)
assert(#serverEvents == 1, 'duplicate ready for the same NUI boot requested another session')

nuiCallbacks.ready({ bootId = 'boot-b' }, function(response) assert(response.ok) end)
assert(#serverEvents == 2, 'a new NUI document did not request a fresh session')
assert(serverEvents[2].name == 'humalike:world:requestVoiceSession')
local replayed = {}
for _, message in ipairs(nuiMessages) do replayed[message.type] = true end
assert(replayed['voice:keybind'], 'new NUI document did not receive the key binding')
local keybind
for _, message in ipairs(nuiMessages) do
    if message.type == 'voice:keybind' then keybind = message end
end
assert(keybind.binding == 't_PTT', 'modal did not receive the humalike mapping key')
assert(replayed['voice:ptt'], 'new NUI document did not receive current PTT state')
assert(replayed['voice:targets'], 'new NUI document did not receive direct NPC targets')
assert(replayed['voice:cabin'], 'new NUI document did not receive current cabin state')
assert(replayed['game:realtime'], 'new NUI document did not receive current realtime state')
assert(replayed['game:listener'], 'new NUI document did not receive current listener state')
handlers['humalike:world:voiceReconnect']()
assert(nuiMessages[#nuiMessages].type == 'voice:reconnect',
    'voice assignment change did not request a NUI reconnect')

-- The PTT poll reads the shared game key every 50 ms instead of every frame.
dofile('client/ptt.lua')
local controlDown = false
function IsControlPressed() return controlDown end
function IsDisabledControlPressed() return false end
function PlayerPedId() return 0 end
function DoesEntityExist() return false end
function Wait(ms) coroutine.yield(ms) end
local poll = coroutine.create(threads[1])
local _, waited = coroutine.resume(poll)
assert(waited == 50, 'a shared key is polled at 50 ms')
controlDown = true
_, waited = coroutine.resume(poll)
assert(nuiMessages[#nuiMessages].type == 'voice:ptt' and nuiMessages[#nuiMessages].active == true,
    'a press on the shared key is picked up on the next poll')
controlDown = false
function GetControlInstructionalButton(_, control) return control == 249 and 't_V' or 't_PTT' end
nuiCallbacks.ready({ bootId = 'boot-c' }, function(response) assert(response.ok) end)
_, waited = coroutine.resume(poll)
assert(waited == 100, 'a key of its own needs only the busy poll')
print('session_ready: ok')
