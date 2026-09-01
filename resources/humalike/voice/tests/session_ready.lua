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
function CreateThread() end
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

HumalikeVoiceNativeAudio = { Status = function() return {} end }
HumalikeVoicePtt = {}
local directTargetsAvailable
HumalikeNpcDirectTargets = {
    Subscribe = function(callback) callback({ 'npc-1' }) end,
    SetAvailable = function(value) directTargetsAvailable = value end,
    Lock = function() end,
    Unlock = function() end,
}

assert(loadfile('client/main.lua'))()
assert(type(nuiCallbacks.ready) == 'function')
assert(type(handlers['humalike:world:registrationRequested']) == 'function')

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
print('session_ready: ok')
