local configuredPeds = {}

local function configurePersistentPed(ped, entry)
    SetEntityCoordsNoOffset(ped, entry.x, entry.y, entry.z, false, false, false)
    SetEntityHeading(ped, entry.heading)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, false)
    SetEntityCanBeDamaged(ped, true)
    SetEntityMaxHealth(ped, 1000000)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedSuffersCriticalHits(ped, false)
    SetPedDiesWhenInjured(ped, false)
    HumalikeNpcReactions.Own(ped, true)
end

CreateThread(function()
    while true do
        Wait(1000)
        local activePeds = {}

        for npcId, ped in pairs(LoadedPeds or {}) do
            if ped and DoesEntityExist(ped) then
                activePeds[ped] = true
                local entry = KnownNpcs and KnownNpcs[npcId] or nil
                if entry and entry.type == 'static' then
                    if NetworkHasControlOfEntity(ped) then
                        local signature = ('%s:%s'):format(
                            NetworkGetNetworkIdFromEntity(ped),
                            tostring(Entity(ped).state.humalike_runtime_token))
                        if configuredPeds[ped] ~= signature then
                            configurePersistentPed(ped, entry)
                            configuredPeds[ped] = signature
                        else
                            FreezeEntityPosition(ped, true)
                            HumalikeNpcReactions.Own(ped)
                            if IsPedFleeing(ped)
                                and not (IsActionControlled and IsActionControlled(ped)) then
                                ClearPedTasks(ped)
                            end
                        end
                    else
                        configuredPeds[ped] = nil
                    end
                else
                    configuredPeds[ped] = nil
                end
            end
        end

        for ped in pairs(configuredPeds) do
            if not activePeds[ped] then configuredPeds[ped] = nil end
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then configuredPeds = {} end
end)
