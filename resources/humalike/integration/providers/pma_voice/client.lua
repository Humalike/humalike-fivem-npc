local RESOURCE = 'pma-voice'
local started = GetResourceState(RESOURCE) == 'started'

-- Change handlers run before the bag is written, so the new channel is the
-- argument, never LocalPlayer.state.
local function setCall(callChannel)
    HumalikeVoiceBusy.Set('pma-voice:call', started and (tonumber(callChannel) or 0) ~= 0)
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
    setCall(LocalPlayer.state.callChannel)
end)

-- busy.lua drops every 'pma-voice:' reason when the resource stops.
AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == RESOURCE then started = false end
end)
