
KnownNpcs = {}  -- npc_id (string) -> NpcRosterEntry-shaped table
LoadedPeds = {} -- npc_id (string) -> ped handle

-- The npc id a ped carries. The lease index and the roster binding know it for
-- nothing; the ped's state bag (a dozen microseconds a read) is asked only
-- about a ped neither of them holds.
function HumalikeNpcIdOfPed(ped)
    local npcId = AmbientPedNpcIds and AmbientPedNpcIds[ped]
    if npcId ~= nil then return npcId end
    for id, loaded in pairs(LoadedPeds) do
        if loaded == ped then return id end
    end
    return DoesEntityExist(ped) and Entity(ped).state.humalike_npc_id or nil
end

function ResolveNpcPed(npcId)
    local staticPed = LoadedPeds[npcId]
    if staticPed and DoesEntityExist(staticPed) then return staticPed end
    local ambientPed = AmbientPeds and AmbientPeds[npcId] or nil
    if ambientPed and DoesEntityExist(ambientPed) then return ambientPed end
    return nil
end

local function clearPersistentBinding(npcId)
    local ped = LoadedPeds[npcId]
    LoadedPeds[npcId] = nil
    if ped then TriggerEvent('humalike:npc:persistentPedRemoved', npcId, ped) end
end

RegisterNetEvent('humalike:npc:rosterSnapshot')
AddEventHandler('humalike:npc:rosterSnapshot', function(entries)
    HumalikeDebug('received roster snapshot: %d npc(s)', #entries)
    for _, entry in ipairs(entries) do
        KnownNpcs[entry.npc_id] = entry
    end
end)

RegisterNetEvent('humalike:npc:npcAdded')
AddEventHandler('humalike:npc:npcAdded', function(entry)
    HumalikeDebug('npc added: %s (%s)', entry.npc_id, entry.name)
    KnownNpcs[entry.npc_id] = entry
end)

RegisterNetEvent('humalike:npc:npcRemoved')
AddEventHandler('humalike:npc:npcRemoved', function(npcId)
    HumalikeDebug('npc removed: %s', npcId)
    KnownNpcs[npcId] = nil
    clearPersistentBinding(npcId)
end)
RegisterNetEvent('humalike:npc:playAction')
AddEventHandler('humalike:npc:playAction', function(npcId, actionKey, params)
    local ped = ResolveNpcPed(npcId)
    if not ped or not DoesEntityExist(ped) then
        HumalikeDebug('playAction %s for npc %s ignored -- not spawned locally', actionKey, npcId)
        return
    end
    local reporter = Entity(ped).state.humalike_position_reporter
    if reporter ~= GetPlayerServerId(PlayerId()) then return end
    local handler = NpcActions and NpcActions[actionKey]
    if not handler then
        print(('[humalike-npc] no local handler for action %q'):format(actionKey))
        return
    end
    HumalikeDebug('playing action %s on npc %s', actionKey, npcId)
    handler(ped, params or {})
end)

RegisterNetEvent('humalike:npc:playAmbientAction')
AddEventHandler('humalike:npc:playAmbientAction', function(npcId, entityId, leaseToken, actionKey, params)
    local entry = AmbientNpcEntries and AmbientNpcEntries[npcId] or nil
    local ped = AmbientPeds and AmbientPeds[npcId] or nil
    if not entry or entry.entity_id ~= entityId or entry.lease_token ~= leaseToken
        or not ped or not DoesEntityExist(ped) then
        HumalikeDebug('playAmbientAction %s for npc %s ignored -- lease not active locally',
            actionKey, npcId)
        return
    end
    if not NetworkHasControlOfEntity(ped) then return end
    local handler = NpcActions and NpcActions[actionKey]
    if not handler then
        print(('[humalike-npc] no local handler for action %q'):format(actionKey))
        return
    end
    HumalikeDebug('playing ambient action %s on npc %s', actionKey, npcId)
    handler(ped, params or {})
end)

CreateThread(function()
    Wait(1000)
    TriggerServerEvent('humalike:npc:requestRoster')

    while true do
        local unresolved = false
        for npcId, entry in pairs(KnownNpcs) do
            local ped = LoadedPeds[npcId]
            if not ped or not DoesEntityExist(ped) then
                unresolved = true
                if ped then clearPersistentBinding(npcId) end
                local networkId = tonumber(entry.network_id)
                if networkId and networkId > 0 and NetworkDoesEntityExistWithNetworkId(networkId) then
                    ped = NetworkGetEntityFromNetworkId(networkId)
                    if ped and ped > 0 and DoesEntityExist(ped) then
                        StopPedSpeaking(ped, true)
                        DisablePedPainAudio(ped, true)
                        LoadedPeds[npcId] = ped
                        TriggerEvent('humalike:npc:persistentPedAssigned', npcId, ped, entry)
                        HumalikeDebug('bound persistent npc %s to network entity %d', npcId, networkId)
                    end
                end
            end
        end
        Wait(unresolved and 1000 or 2000)
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    LoadedPeds = {}
end)
