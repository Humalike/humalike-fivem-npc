local handler
local reports = {}

function RegisterNetEvent(name, callback)
    assert(name == 'QBCore:Command:ShowMe3D')
    handler = callback
end
function PlayerId() return 4 end
function GetPlayerServerId(playerId)
    assert(playerId == 4)
    return 7
end
function TriggerServerEvent(name, text)
    reports[#reports + 1] = { name = name, text = text }
end

dofile('../integration/providers/qbcore/world_events_client.lua')

handler(7, 'patrzy na zegar')
assert(#reports == 1)
assert(reports[1].name == 'humalike:integration:qbcore:rpAction')
assert(reports[1].text == 'patrzy na zegar')

handler(8, 'ignored: another player')
handler(7, 42)
assert(#reports == 1)

print('qbcore_world_events_client: ok')
