local handler
local reports = {}

function RegisterNetEvent(name, callback)
    assert(name == 'esx_rpchat:sendProximityMessage')
    handler = callback
end

function PlayerId() return 4 end
function GetPlayerServerId(playerId)
    assert(playerId == 4)
    return 7
end

function TriggerServerEvent(name, kind, text)
    reports[#reports + 1] = { name = name, kind = kind, text = text }
end

dofile('../integration/providers/esx/world_events_client.lua')

handler(7, 'name', 'spogląda na zegarek', { 255, 0, 0 })
handler(7, 'name', 'jest późno', { 0, 0, 255 })
assert(#reports == 2)
assert(reports[1].kind == 'me')
assert(reports[2].kind == 'do')

handler(8, 'name', 'ignored', { 255, 0, 0 })
handler(7, 'name', 'ignored', { 1, 2, 3 })
assert(#reports == 2)

print('esx_world_events_client: ok')
