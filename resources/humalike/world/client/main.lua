exports('RegisterNpc', function(value)
    if type(value) ~= 'table' then return false, 'registration must be a table' end
    value = HumalikeWorldContracts.Copy(value)
    value.ownerResource = GetInvokingResource() or 'unknown'
    return HumalikeWorldRegistry.Register(value)
end)
exports('UpdateNpc', function(npcId, patch)
    return HumalikeWorldRegistry.Update(npcId, patch, GetInvokingResource() or 'unknown')
end)
exports('UnregisterNpc', function(npcId)
    return HumalikeWorldRegistry.Unregister(npcId, GetInvokingResource() or 'unknown')
end)
exports('SetNpcActivity', function(npcId, activity)
    return HumalikeWorldRegistry.SetActivity(npcId, activity, GetInvokingResource() or 'unknown')
end)
exports('SetVoiceMode', function(mode) return HumalikeWorldCollector.SetVoiceMode(mode) end)
exports('GetLocalPlayerState', function()
    return HumalikeWorldContracts.Copy(HumalikeWorldCollector.latest)
end)
exports('GetCabinMembership', function()
    return HumalikeWorldContracts.Copy(HumalikeWorldCabin.membership)
end)
exports('GetListenerState', function()
    return HumalikeWorldContracts.Copy(HumalikeWorldCollector.listener)
end)
exports('GetStatus', function()
    return {
        v = 1,
        bootId = HumalikeWorldCollector.bootId,
        collectorSequence = HumalikeWorldCollector.sequence,
        npcCount = HumalikeWorldRegistry.Count(),
        registryRevision = HumalikeWorldRegistry.revision,
        cabin = {
            epoch = HumalikeWorldCabin.epoch,
            revision = HumalikeWorldCabin.revision,
            active = HumalikeWorldCabin.membership ~= nil,
            membership = HumalikeWorldContracts.Copy(HumalikeWorldCabin.membership),
        },
        tracks = HumalikeWorldTrack.count,
        npcEdge = {
            enabled = WorldConfig.npcEdge.enabled,
            connected = HumalikeWorldNpcEdge.connected,
            ticketPending = HumalikeWorldNpcEdge.ticketPending,
            sentFrames = HumalikeWorldNpcEdge.sentFrames,
            coalescedFrames = HumalikeWorldNpcEdge.coalescedFrames,
            lastError = HumalikeWorldNpcEdge.lastError,
        },
    }
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        SendNUIMessage({ type = 'shutdown' })
        return
    end
    local removed = HumalikeWorldRegistry.RemoveOwner(resource)
    if removed > 0 then HumalikeWorldDebug('removed %d NPC registrations owned by %s', removed, resource) end
end)

CreateThread(function()
    HumalikeSettings.Wait(5000)
    HumalikeWorldCollector.Start()
    HumalikeWorldTrack.Start()
    HumalikeWorldNpcEdge.Start()
    Wait(0)
    TriggerEvent('humalike:world:registrationRequested', HumalikeWorldCollector.bootId)
end)
