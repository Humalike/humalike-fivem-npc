local events, timeouts = {}, {}
local buckets = { [7] = 0 }

json = {
    encode = function(value)
        if value == nil then return 'null' end
        if type(value) ~= 'table' then return tostring(value) end
        local keys, result = {}, {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, key in ipairs(keys) do result[#result + 1] = tostring(key) .. '=' .. json.encode(value[key]) end
        return '{' .. table.concat(result, ',') .. '}'
    end,
}
os.time = function() return 100 end
GetGameTimer = function() return 200 end
GetPlayerRoutingBucket = function(player) return buckets[tonumber(player)] end
RegisterNetEvent = function() end
AddEventHandler = function(name, callback) events[name] = callback end
TriggerEvent = function(name, payload)
    events.emitted = events.emitted or {}
    events.emitted[#events.emitted + 1] = { name = name, payload = payload }
end
SetTimeout = function(_, callback) timeouts[#timeouts + 1] = callback end

dofile('server/contracts.lua')
dofile('server/authority.lua')

assert(HumalikeWorldAuthority.epoch:match(
    '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-8%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'))

assert(HumalikeWorldAuthority.SetIdentity(7, {
    characterId = 'char-7', name = 'Player', metadata = { npc = { appearance = { model = 123 } } },
}))
local state = HumalikeWorldAuthority.players[7]
assert(state.routingBucket == 0 and state.generation == 1)
local revision = HumalikeWorldAuthority.revision
assert(HumalikeWorldAuthority.SetIdentity(7, {
    characterId = 'char-7', name = 'Player', metadata = { npc = { appearance = { model = 123 } } },
}))
assert(HumalikeWorldAuthority.revision == revision)

assert(HumalikeWorldAuthority.Patch(7, { dead = true }))
assert(state.dead and state.generation == 2)
revision = HumalikeWorldAuthority.revision
assert(HumalikeWorldAuthority.Patch(7, { dead = true }))
assert(HumalikeWorldAuthority.revision == revision)
buckets[7] = 12
events.onPlayerBucketChange('7', 12, 0)
assert(state.routingBucket == 0 and #timeouts == 1)
timeouts[1]()
assert(state.routingBucket == 12 and state.generation == 3)

source = 7
events.playerDropped()
assert(HumalikeWorldAuthority.players[7] == nil)

print('server_authority: ok')
