HumalikeSettings = { applied = false }

RegisterNetEvent('humalike:settings')
AddEventHandler('humalike:settings', function(snapshot)
    if not HumalikeApplyConvarSnapshot(snapshot) then return end
    HumalikeSettings.applied = true
    TriggerEvent('humalike:settings:applied')
end)

CreateThread(function()
    local delay = 1000
    while not HumalikeSettings.applied do
        TriggerServerEvent('humalike:settings:request')
        Wait(delay)
        delay = math.min(delay * 2, 15000)
    end
end)
