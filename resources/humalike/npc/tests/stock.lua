local exported, posts, printed = {}, {}, {}
local answer = { ok = true, status = 200, body = { stock = { map = 50, bread = 'unlimited' } } }
local bound = true
function exports(name, callback) exported[name] = callback end
function HumalikeDebug() end
function print(line) printed[#printed + 1] = line end
json = { encode = function() return '{}' end }
promise = { new = function()
    local p = {}
    function p:resolve(value) self.value = value end
    return p
end }
Citizen = { Await = function(p)
    assert(p.value ~= nil, 'awaited before the poster answered')
    return p.value
end }
HumaLike = {
    PostEdgeAction = function(name, payload, callback)
        posts[#posts + 1] = { name = name, payload = payload }
        callback(answer.ok, answer.status, answer.body)
    end,
    ErrorCode = function(body)
        return type(body) == 'table' and type(body.error) == 'table' and body.error.code or nil
    end,
}
local SAL, EXT, GHOST = '6eb4f0a5-1111-4222-8333-444455556666',
    'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', '00000000-0000-4000-8000-000000000000'
NpcRegistry = { [SAL] = { type = 'static' }, [EXT] = { type = 'external' } }
HumalikeNpcRuntimeControl = { Target = function(npcId)
    if npcId == EXT and bound then return 'external', NpcRegistry[EXT] end
    return nil
end }

dofile('../server/core/export_result.lua')
dofile('server/http.lua')
dofile('server/stock.lua')

local set = exported.SetNpcStock
local function refused(npcId, stock, code)
    local result = set(npcId, stock)
    assert(result.ok == false and result.error == code,
        ('expected %s, got %s'):format(code, tostring(result.error)))
end

refused(nil, { map = 1 }, 'invalid_npc')
refused(42, { map = 1 }, 'invalid_npc')
refused('sal', { map = 1 }, 'invalid_npc')
refused(SAL .. '0', { map = 1 }, 'invalid_npc')
refused(GHOST, { map = 1 }, 'npc_not_found')
bound = false
refused(EXT, { map = 1 }, 'npc_not_bound')
bound = true
refused(SAL, nil, 'invalid_stock')
refused(SAL, 'map', 'invalid_stock')
refused(SAL, {}, 'invalid_stock')
refused(SAL, { Map = 1 }, 'invalid_item:Map')
refused(SAL, { ['treasure map'] = 1 }, 'invalid_item:treasure map')
refused(SAL, { 'map' }, 'invalid_item:1')
refused(SAL, { [('m'):rep(49)] = 1 }, 'invalid_item:' .. ('m'):rep(49))
refused(SAL, { map = -1 }, 'invalid_count:map')
refused(SAL, { map = 1.5 }, 'invalid_count:map')
refused(SAL, { map = 1000001 }, 'invalid_count:map')
refused(SAL, { map = 0 / 0 }, 'invalid_count:map')
refused(SAL, { map = '50' }, 'invalid_count:map')
refused(SAL, { map = 'lots' }, 'invalid_count:map')
refused(SAL, { map = true }, 'invalid_count:map')
local crowded = {}
for index = 1, 33 do crowded['item_' .. index] = 1 end
refused(SAL, crowded, 'too_many_items')
assert(#posts == 0, 'a refused shelf never reaches the poster')

local result = set(SAL, { map = 50.0, bread = 'unlimited', [('m'):rep(48)] = 0, ['a.b-c_9'] = 1000000 })
assert(result.ok, result.error)
assert(#posts == 1 and posts[1].name == 'set_npc_stock')
local body = posts[1].payload
assert(body.npc_id == SAL)
assert(body.stock.map == 50 and math.type(body.stock.map) == 'integer')
assert(body.stock.bread == 'unlimited')
assert(body.stock[('m'):rep(48)] == 0 and body.stock['a.b-c_9'] == 1000000)
local width = 0
for _ in pairs(body.stock) do width = width + 1 end
assert(width == 4)
assert(result.value.stock == answer.body.stock, 'the answer carries what HumaLike stored')
local full = {}
for index = 1, 32 do full['item_' .. index] = index end
assert(set(EXT, full).ok and posts[2].payload.npc_id == EXT)
-- No shelf in the answer falls back to what was sent.
answer = { ok = true, status = 200, body = {} }
result = set(SAL, { cola = 3 })
assert(result.ok and result.value.stock.cola == 3)

answer = { ok = false, status = 400, body = { error = { code = 'VALIDATION_ERROR',
    details = { { field = 'stock.map', message = 'too many' } } } } }
refused(SAL, { map = 1 }, 'VALIDATION_ERROR')
assert(printed[#printed]:find('HTTP 400 VALIDATION_ERROR: stock.map: too many', 1, true), printed[#printed])
answer = { ok = false, status = 404, body = { error = { code = 'NPC_NOT_FOUND' } } }
refused(SAL, { map = 1 }, 'NPC_NOT_FOUND')
answer = { ok = false, status = 500, body = nil }
refused(SAL, { map = 1 }, 'http_500')
answer = { ok = false, status = 0, body = nil }
refused(SAL, { map = 1 }, 'runtime_not_ready')

print('stock: ok')
