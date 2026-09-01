local handler
local reports = {}

function AddStateBagChangeHandler(key, _, callback)
    assert(key == 'me')
    handler = callback
end

function GetPlayerFromStateBagName(bagName)
    return bagName == 'player:7' and 7 or 0
end

HumalikePlayer = { Name = function() return 'qbox' end }

function HumalikeReportPlayerEvent(source, event)
    reports[#reports + 1] = { source = source, event = event }
end

dofile('../integration/providers/qbox/world_events.lua')

handler('player:7', 'me', 'wzdycha ciężko')
assert(#reports == 1)
assert(reports[1].source == 7)
assert(reports[1].event.type == 'rp_action')
assert(reports[1].event.kind == 'me')
assert(reports[1].event.text == 'wzdycha ciężko')

handler('player:7', 'me', nil)
handler('entity:7', 'me', 'ignored')
assert(#reports == 1)

HumalikePlayer.Name = function() return 'standalone' end
handler('player:7', 'me', 'ignored')
assert(#reports == 1)

print('qbox_world_events: ok')
