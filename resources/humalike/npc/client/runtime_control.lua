HumalikeNpcRuntimeControl = HumalikeNpcRuntimeControl or {}

local revision = -1
local controls = {}

function HumalikeNpcRuntimeControl.IsControlled(npcId, domain)
    local held = controls[npcId]
    return held ~= nil and (held.all == true or held[domain] == true)
end

function HumalikeNpcRuntimeControl.IsVoiceUnavailable(npcId)
    return HumalikeNpcRuntimeControl.IsControlled(npcId, 'speech')
        or HumalikeNpcRuntimeControl.IsControlled(npcId, 'perception')
end

RegisterNetEvent('humalike:npc:runtimeControlSnapshot')
AddEventHandler('humalike:npc:runtimeControlSnapshot', function(nextRevision, snapshot)
    nextRevision = tonumber(nextRevision)
    if not nextRevision or nextRevision <= revision or type(snapshot) ~= 'table' then return end
    revision = nextRevision
    controls = snapshot
    if HumalikeNpcPopulationClient and HumalikeNpcPopulationClient.RebuildPace then
        HumalikeNpcPopulationClient.RebuildPace()
    end
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('humalike:npc:requestRuntimeControls')
end)
