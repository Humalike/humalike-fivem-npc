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
local rawMessages = {}
function SendNuiMessage(message) rawMessages[#rawMessages + 1] = message end
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

dofile('../world/client/pulse.lua')
dofile('client/busy.lua')
assert(loadfile('client/main.lua'))()
assert(type(nuiCallbacks.ready) == 'function')
assert(type(handlers['humalike:world:registrationRequested']) == 'function')
assert(type(handlers['humalike:world:voiceReconnect']) == 'function')
collectorSubscribers.listener({ position = { x = 2, y = 0, z = 0 }, forward = { x = 1, y = 0, z = 0 } })
assert(rawMessages[#rawMessages] == '{"type":"game:listener","position":{"x":2.000,"y":0.000,"z":0.000},"forward":{"x":1.0000,"y":0.0000,"z":0.0000}}',
    'the listener goes straight to the NUI, encoded by hand')
collectorSubscribers.motion({ v = 1, bootId = 'boot', sequence = 2, clientTimeMs = 1234,
    position = { x = 1, y = 2, z = 3 }, velocity = { x = 0, y = 0, z = 0 }, heading = 90,
    vehicle = { networkId = 501, seat = -1, kind = 'car' }, effectiveVoiceDistance = 15,
    voiceMode = 2, zone = 'DOWNT', flags = { dead = false, paused = true } })
assert(rawMessages[#rawMessages] == '{"type":"game:realtime","state":{"v":1,"type":"player_motion","bootId":"boot","sequence":2,"clientTimeMs":1234,"position":{"x":1.000,"y":2.000,"z":3.000},"velocity":{"x":0.000,"y":0.000,"z":0.000},"heading":90.00,"vehicle":{"networkId":501,"seat":-1},"effectiveVoiceDistance":15.00,"voiceMode":2,"zone":"DOWNT","flags":{"dead":false,"paused":true}}}',
    'and so does player motion, without the vehicle kind the voice router never asked for')
collectorSubscribers.motion({ position = { x = 1, y = 2, z = 3 }, velocity = {}, flags = {} })
assert(rawMessages[#rawMessages]:find('"zone":""', 1, true) and not rawMessages[#rawMessages]:find('vehicle', 1, true),
    'a sample on foot has no vehicle')
local listenerDemand
HumalikeWorldCollector.SetListenerDemand = function(active) listenerDemand = active end
nuiCallbacks.listenerDemand({ active = true }, function() end)
assert(listenerDemand == true, 'the NUI drives the fast listener sampling')
nuiCallbacks.listenerDemand({}, function() end)
assert(listenerDemand == false)

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

dofile('client/ptt.lua')
local controlDown = false
function IsControlPressed() return controlDown end
function IsDisabledControlPressed() return false end
function PlayerPedId() return 0 end
function DoesEntityExist() return false end
local now = 1000
function GetGameTimer() return now end
assert(HumalikePulse.Run(now) == 50, 'a shared key is polled at 50 ms, on the shared pulse')
controlDown = true
now = 1050
HumalikePulse.Run(now)
assert(nuiMessages[#nuiMessages].type == 'voice:ptt' and nuiMessages[#nuiMessages].active == true,
    'a press on the shared key is picked up on the next poll')
controlDown = false
function GetControlInstructionalButton(_, control) return control == 249 and 't_V' or 't_PTT' end
nuiCallbacks.ready({ bootId = 'boot-c' }, function(response) assert(response.ok) end)
now = 1100
assert(HumalikePulse.Run(now) == 100, 'a key of its own needs only the busy poll')

rawMessages = {}
HumalikePulse.Every('samples', 100, function()
    collectorSubscribers.listener({ position = { x = 2, y = 0, z = 0 }, forward = { x = 1, y = 0, z = 0 } })
    collectorSubscribers.motion({ position = { x = 1, y = 2, z = 3 }, velocity = {}, flags = {} })
end)
now = 1200
HumalikePulse.Run(now)
assert(#rawMessages == 1 and rawMessages[1]:find('^{"type":"batch","messages":%[{"type":"game:listener"')
    and rawMessages[1]:find(',{"type":"game:realtime"', 1, true), 'listener and motion in one cross-process call')
print('session_ready: ok')
