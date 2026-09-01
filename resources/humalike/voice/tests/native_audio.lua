local handlers, timeouts, writes = {}, {}, {}
local now, pmaState, muted = 100, 'started', {}
GetResourceState = function() return pmaState end
GetPlayerServerId = function() return 99 end
PlayerId = function() return 1 end
GetGameTimer = function() return now end
MumbleSetVolumeOverrideByServerId = function(serverId, volume)
    writes[#writes + 1] = { serverId, volume }
end
exports = setmetatable({}, { __index = function()
    return { isPlayerMuted = function(_, serverId) return muted[serverId] == true end }
end })
RegisterNetEvent = function() end
AddEventHandler = function(name, callback) handlers[name] = callback end
SetTimeout = function(_, callback) timeouts[#timeouts + 1] = callback end
CreateThread = function() end
Wait = function() end
GetCurrentResourceName = function() return 'humalike' end

dofile('client/native_audio.lua')
HumalikeVoiceNativeAudio.UpdateSnapshot({ 7 })
assert(writes[#writes][1] == 7 and writes[#writes][2] == 0.0)
handlers['pma-voice:addPlayerToCall'](7)
assert(HumalikeVoiceNativeAudio.overridden[7] == nil)
handlers['pma-voice:removePlayerFromCall'](7)
timeouts[#timeouts]()
assert(writes[#writes][2] == 0.0)
HumalikeVoiceNativeAudio.UpdateSnapshot({})
assert(writes[#writes][2] == -1.0)
muted[7] = true
HumalikeVoiceNativeAudio.UpdateSnapshot({ 7 })
HumalikeVoiceNativeAudio.UpdateSnapshot({})
assert(writes[#writes][2] == 0.0)
HumalikeVoiceNativeAudio.UpdateSnapshot({ 7 })
handlers.onClientResourceStop('humalike')
assert(next(HumalikeVoiceNativeAudio.overridden) == nil)
pmaState = 'started'
HumalikeVoiceNativeAudio.UpdateSnapshot({ 7 })
HumalikeVoiceNativeAudio.callPlayers[7] = true
HumalikeVoiceNativeAudio.radioPlayers[7] = true
pmaState = 'stopping'
handlers.onClientResourceStop('pma-voice')
assert(next(HumalikeVoiceNativeAudio.callPlayers) == nil)
assert(next(HumalikeVoiceNativeAudio.radioPlayers) == nil)
assert(next(HumalikeVoiceNativeAudio.overridden) == nil)
assert(writes[#writes][2] == -1.0)
print('native_audio: ok')
