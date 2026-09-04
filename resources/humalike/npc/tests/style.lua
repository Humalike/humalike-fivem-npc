-- A style seed maps onto a model's variation counts deterministically, and
-- differently for different seeds.
function AddEventHandler() end
dofile('client/style.lua')

local counts = { { 3, 0 }, { 1, 0 }, { 4, 0 }, { 2, 0 } }
local a = HumalikeStyleFor(12345, counts)
local b = HumalikeStyleFor(12345, counts)
local c = HumalikeStyleFor(54321, counts)
for i = 1, #counts do
    assert(a[i][1] == b[i][1] and a[i][2] == b[i][2], 'same seed, same look')
    assert(a[i][1] >= 0 and a[i][1] < counts[i][1], 'drawable within count')
end
assert(a[2][1] == 0, 'a single-variant slot always picks 0')
local differs = false
for i = 1, #counts do if a[i][1] ~= c[i][1] then differs = true end end
assert(differs, 'different seeds look different')
assert(#HumalikeStyleFor(nil, counts) == #counts, 'nil seed still maps')
print('style ok')
