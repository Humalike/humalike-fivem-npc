local RESOURCE = 'saltychat'

-- SaltyChat manages phone calls on the server and exposes no client call
-- state; a phone resource reports its calls through SetVoiceBusy. busy.lua
-- drops the reason when SaltyChat stops.
AddEventHandler('SaltyChat_RadioTrafficStateChanged',
    function(_primaryReceive, primaryTransmit, _secondaryReceive, secondaryTransmit)
        if GetResourceState(RESOURCE) ~= 'started' then return end
        HumalikeVoiceBusy.Set('saltychat:radio',
            primaryTransmit == true or secondaryTransmit == true)
    end)
