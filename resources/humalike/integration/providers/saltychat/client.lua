local RESOURCE = 'saltychat'

-- SaltyChat manages phone calls on the server and exposes no client call
-- state; a phone resource reports its calls through SetVoiceBusy.
AddEventHandler('SaltyChat_RadioTrafficStateChanged',
    function(_primaryReceive, primaryTransmit, _secondaryReceive, secondaryTransmit)
        if GetResourceState(RESOURCE) ~= 'started' then return end
        HumalikeVoiceBusy.Set('saltychat:radio',
            primaryTransmit == true or secondaryTransmit == true)
    end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == RESOURCE then HumalikeVoiceBusy.ClearPrefix('saltychat:') end
end)
