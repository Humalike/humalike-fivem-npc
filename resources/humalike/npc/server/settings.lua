-- Every convar the shared config reads goes to the client that asks for it, so
-- `set` in server.cfg is enough for client-side settings.
local lastSentAt = {}

RegisterNetEvent('humalike:settings:request')
AddEventHandler('humalike:settings:request', function()
    local source = source
    if type(source) ~= 'number' or source <= 0 then return end
    local now = GetGameTimer()
    if now - (lastSentAt[source] or -10000) < 1000 then return end
    lastSentAt[source] = now
    TriggerClientEvent('humalike:settings', source, HumalikeConvarSnapshot())
end)

AddEventHandler('playerDropped', function()
    lastSentAt[source] = nil
end)
