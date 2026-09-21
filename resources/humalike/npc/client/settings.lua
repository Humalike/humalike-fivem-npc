HumalikeSettings = { applied = false }

-- Threads that read a setting once at start wait for the server's answer, for
-- at most maxMs; an old server that never answers only delays them.
function HumalikeSettings.Wait(maxMs)
    local deadline = GetGameTimer() + maxMs
    while not HumalikeSettings.applied and GetGameTimer() < deadline do Wait(100) end
    return HumalikeSettings.applied
end

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
