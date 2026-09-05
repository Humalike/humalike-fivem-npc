function AddEventHandler() end
dofile('client/style.lua')

local counts = { { 3, 0 }, { 1, 0 }, { 4, 0 }, { 2, 0 } }
local a = HumalikeNpcStyle.Choices(12345, counts)
local b = HumalikeNpcStyle.Choices(12345, counts)
local c = HumalikeNpcStyle.Choices(54321, counts)
for i = 1, #counts do
    assert(a[i][1] == b[i][1] and a[i][2] == b[i][2], 'same seed, same look')
    assert(a[i][1] >= 0 and a[i][1] < counts[i][1], 'drawable within count')
end
assert(a[2][1] == 0, 'a single-variant slot always picks 0')
local differs = false
for i = 1, #counts do if a[i][1] ~= c[i][1] then differs = true end end
assert(differs, 'different seeds look different')
assert(#HumalikeNpcStyle.Choices(nil, counts) == #counts, 'nil seed still maps')
print('style ok')

local set, props, cleared = {}, {}, {}
function DoesEntityExist() return true end
function IsPedAPlayer() return false end
function NetworkHasControlOfEntity() return true end
function GetNumberOfPedDrawableVariations(_, c) return c == 3 and 4 or 1 end
function GetNumberOfPedTextureVariations() return 2 end
function GetNumberOfPedPropDrawableVariations() return 3 end
function GetNumberOfPedPropTextureVariations() return 1 end
function SetPedComponentVariation(_, c, d, t) set[c] = { d, t } end
function SetPedPropIndex(_, p, d, t) props[p] = { d, t } end
function ClearPedProp(_, p) cleared[p] = true end
assert(HumalikeNpcStyle.ApplyExplicit(7, { components = { ["3"] = { 2, 5 }, ["4"] = { 9, 0 } }, props = { ["0"] = { -1, 0 }, ["1"] = { 1, 0 } } }))
assert(set[3][1] == 2 and set[3][2] == 1, 'drawable set, texture wrapped into range')
assert(set[4] == nil, 'a drawable past the model count is ignored')
assert(cleared[0] and props[1][1] == 1, 'props: -1 clears, index sets')
print('explicit style ok')
