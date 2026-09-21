local RESOURCE = 'pma-voice'
local started = GetResourceState(RESOURCE) == 'started'

-- Change handlers run before the bag is written, so the new channel is the
-- argument, never LocalPlayer.state.
local function setCall(callChannel)
    HumalikeVoiceBusy.Set('pma-voice:call', HumalikeVoicePtt.CallActive(callChannel, started))
end

AddEventHandler('pma-voice:radioActive', function(active)
    HumalikeVoiceBusy.Set('pma-voice:radio', started and active == true)
end)

AddStateBagChangeHandler('callChannel', nil, function(bagName, _, value)
    if GetPlayerFromStateBagName(bagName) ~= PlayerId() then return end
    setCall(tonumber(value) or 0)
end)

CreateThread(function()
    setCall(LocalPlayer.state.callChannel)
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end
    started = true
    HumalikeVoiceBusy.ClearPrefix('pma-voice:')
    setCall(LocalPlayer.state.callChannel)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    started = false
    HumalikeVoiceBusy.ClearPrefix('pma-voice:')
end)
