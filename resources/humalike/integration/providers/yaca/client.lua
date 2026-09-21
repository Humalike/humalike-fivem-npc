local RESOURCE = 'yaca-voice'
local POLL_MS = 500
local started = GetResourceState(RESOURCE) == 'started'
local generation = 0
local talking = {}

-- yaca reports each radio channel on its own; busy while any transmits.
AddEventHandler('yaca:external:isRadioTalking', function(state, channel)
    if not started then return end
    talking[channel or 'primary'] = state == true or nil
    HumalikeVoiceBusy.Set('yaca-voice:radio', next(talking) ~= nil)
end)

-- yaca exposes the call state as an export only, so it is polled while it runs.
local function pollCalls()
    local mine = generation
    CreateThread(function()
        while started and mine == generation do
            local ok, inCall = pcall(function() return exports[RESOURCE]:isInCall() end)
            HumalikeVoiceBusy.Set('yaca-voice:call', ok and inCall == true)
            Wait(POLL_MS)
        end
    end)
end

if started then pollCalls() end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end
    started = true
    talking = {}
    pollCalls()
end)

-- busy.lua drops every 'yaca-voice:' reason when the resource stops.
AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    started = false
    generation = generation + 1
    talking = {}
end)
