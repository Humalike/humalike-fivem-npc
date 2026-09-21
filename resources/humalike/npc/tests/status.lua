local command
local lines = {}
local originalPrint = print

HumaLike = {}
RegisterCommand = function(name, callback, restricted)
    assert(name == 'humalike_status')
    assert(restricted == true)
    command = callback
end
print = function(message)
    lines[#lines + 1] = message
end

dofile('../server/core/status.lua')

HumalikeGetProviderStatus = function()
    return {
        apiVersion = 1,
        runtimeEpoch = 'test-epoch',
        domains = {
            player = {
                setting = 'auto',
                state = 'selected',
                selected = { name = 'standalone' },
                candidates = { { name = 'standalone', state = 'available' } },
            },
            inventory = {
                setting = 'auto', state = 'unavailable', selected = false,
                candidates = {}, reason = 'no available provider',
            },
            dispatch = {
                setting = 'none', state = 'disabled', selected = false,
                candidates = {},
            },
            actions = {
                setting = 'none', state = 'disabled', selected = false,
                candidates = {},
            },
        },
    }
end

command(0)

assert(#lines == 6)
assert(lines[2]:find('api=1 epoch=test%-epoch'))
assert(lines[3]:find('domain=player'))
assert(lines[3]:find('selected=standalone'))
assert(lines[4]:find('reason=no available provider'))

HumalikeNpcPopulation = {
    Enabled = function() return true end,
    Bodies = function() return { {}, {}, {} } end,
    Vehicles = function() return false end,
    Drivers = function() return 2 end,
}
lines = {}
command(0)
assert(#lines == 7)
assert(lines[2] == '[humalike] population enabled=true bodies=3 npc_vehicles=false drivers=2')

print = originalPrint
io.write('status tests passed\n')
