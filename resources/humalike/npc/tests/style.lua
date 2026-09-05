function AddEventHandler() end
dofile('client/style.lua')

local a, b, c = HumalikeNpcStyle.Roll(12345), HumalikeNpcStyle.Roll(12345), HumalikeNpcStyle.Roll(54321)
local same, differs = true, false
for _ = 1, 16 do
    local x, y, z = a(1000), b(1000), c(1000)
    assert(x >= 0 and x < 1000, 'roll within count')
    same = same and x == y
    differs = differs or x ~= z
end
assert(same, 'same seed, same look')
assert(differs, 'different seeds look different')
assert(HumalikeNpcStyle.Roll(nil)(5) < 5, 'nil seed still rolls')
print('roll ok')

local set, props, cleared = {}, {}, {}
local drawableCounts = { [1] = 1, [3] = 4 }
local propCounts = { [0] = 3, [1] = 3 }
function DoesEntityExist() return true end
function IsPedAPlayer() return false end
function NetworkHasControlOfEntity() return true end
function GetNumberOfPedDrawableVariations(_, c) return drawableCounts[c] or 0 end
function GetNumberOfPedTextureVariations(_, c) return c == 1 and 3 or 2 end
function GetNumberOfPedPropDrawableVariations(_, p) return propCounts[p] or 0 end
function GetNumberOfPedPropTextureVariations() return 1 end
function SetPedComponentVariation(_, c, d, t) set[c] = { d, t } end
function SetPedPropIndex(_, p, d, t) props[p] = { d, t } end
function ClearPedProp(_, p) cleared[p] = true end

assert(HumalikeNpcStyle.ApplySeed(7, 99))
assert(set[1] and set[1][1] == 0 and set[1][2] < 3, 'one drawable, many textures: texture still pinned')
assert(set[3] and set[3][1] < 4 and set[3][2] < 2, 'seeded drawable and texture within counts')
assert(set[0] == nil and set[2] == nil, 'slots without drawables untouched')
assert((props[0] or cleared[0]) and (props[1] or cleared[1]), 'props rolled, worn or cleared')
assert(props[2] == nil and not cleared[2], 'props without drawables untouched')
local first = { set[1][2], set[3][1], set[3][2] }
set = {}
HumalikeNpcStyle.ApplySeed(7, 99)
assert(set[1][2] == first[1] and set[3][1] == first[2] and set[3][2] == first[3], 'seed is deterministic')
print('seeded style ok')

set, props, cleared = {}, {}, {}
assert(HumalikeNpcStyle.ApplyExplicit(7, { components = { ["3"] = { 2, 5 }, ["4"] = { 9, 0 } }, props = { ["0"] = { -1, 0 }, ["1"] = { 1, 0 } } }))
assert(set[3][1] == 2 and set[3][2] == 1, 'drawable set, texture wrapped into range')
assert(set[4] == nil, 'a drawable past the model count is ignored')
assert(cleared[0] and props[1][1] == 1, 'props: -1 clears, index sets')
print('explicit style ok')

set, props, cleared = {}, {}, {}
assert(HumalikeNpcStyle.Dress(7, { style_seed = 99, style = { components = { ["3"] = { 2, 0 } } } }))
assert(set[3][1] == 2 and set[3][2] == 0, 'explicit slot wins over the seed')
assert(set[1] and set[1][1] == 0, 'slots the explicit look omits still come from the seed')
assert(HumalikeNpcStyle.Dress(7, { style_seed = 99 }), 'seed alone dresses')
assert(not HumalikeNpcStyle.Dress(7, {}), 'nothing to apply')
print('dress ok')
