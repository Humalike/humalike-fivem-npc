exports('SetPlayerIdentity', function(playerId, identity)
    return HumalikeWorldAuthority.SetIdentity(playerId, identity)
end)
exports('PatchPlayerState', function(playerId, patch)
    return HumalikeWorldAuthority.Patch(playerId, patch)
end)
exports('ClearPlayerIdentity', function(playerId)
    return HumalikeWorldAuthority.Remove(playerId)
end)
exports('GetPlayerState', function(playerId)
    return HumalikeWorldServerContracts.Copy(HumalikeWorldAuthority.players[tonumber(playerId)])
end)
exports('GetAuthoritySnapshot', function() return HumalikeWorldAuthority.Snapshot() end)
exports('GetCabinMembership', function(playerId)
    return HumalikeWorldServerContracts.Copy(
        HumalikeWorldCabins.playerMembers[tonumber(playerId)])
end)
exports('GetStatus', function()
    local count = 0
    for _ in pairs(HumalikeWorldAuthority.players) do count = count + 1 end
    return { v = 1, epoch = HumalikeWorldAuthority.epoch,
        revision = HumalikeWorldAuthority.revision, playerCount = count,
        runtime = HumaLike.Status(), cabins = HumalikeWorldCabins.Status() }
end)

CreateThread(function()
    Wait(0)
    TriggerEvent('humalike:world:authoritySnapshot', HumalikeWorldAuthority.Snapshot())
    TriggerEvent('humalike:world:registrationRequested', HumalikeWorldAuthority.epoch)
    while true do
        Wait(WorldConfig.authority.snapshotIntervalMs)
        TriggerEvent('humalike:world:authoritySnapshot', HumalikeWorldAuthority.Snapshot())
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        print(('[humalike-world] ready epoch=%s'):format(HumalikeWorldAuthority.epoch))
    end
end)
