local RESOURCE = 'yaca-voice'
local POLL_MS = 500

AddEventHandler('yaca:external:isRadioTalking', function(state)
    if GetResourceState(RESOURCE) ~= 'started' then return end
    HumalikeVoiceBusy.Set('yaca:radio', state == true)
end)

-- yaca exposes the call state as an export only, so it is polled while it runs.
CreateThread(function()
    while true do
        if GetResourceState(RESOURCE) == 'started' then
            local ok, inCall = pcall(function() return exports[RESOURCE]:isInCall() end)
            HumalikeVoiceBusy.Set('yaca:call', ok and inCall == true)
            Wait(POLL_MS)
        else
            Wait(2000)
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == RESOURCE then HumalikeVoiceBusy.ClearPrefix('yaca:') end
end)
