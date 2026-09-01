Config = { AppearancePollIntervalMs = 1000, AppearancePropIds = { 0, 1, 2, 6, 7 } }

local thread
local sent = {}
local step = 0
local ped = 1
local model = 100
local drawables = {}
local textures = {}
local propDrawables = { [0] = -1, [1] = -1, [2] = -1, [6] = -1, [7] = -1 }
local propTextures = {}
local blendOk = true
local blendValues = { [25] = 21, [33] = 2, [57] = 0.34 }
local hairColor = 5
local hairHighlight = -1 -- getter failure sentinel -> the 255 unknown byte
local overlayFound = true
local overlay = { value = 10, colourType = 1, firstColour = 3, secondColour = 0, opacity = 0.77 }
local eyeColor = 4

local mutations = {
    function() end, -- 1: initial read emits the starting outfit + features
    function() end, -- 2: unchanged, nothing sent
    function() drawables[4] = 7; textures[4] = 2 end, -- 3: drawable+texture change
    function() propDrawables[7] = 2; propTextures[7] = -1; propDrawables[0] = 13 end,
    function() end, -- 5: unchanged again
    function() propTextures[0] = 3 end, -- 6: texture-only change still emits
    function() drawables[4] = -1 end,
    function() drawables[4] = 7 end,
    function() textures[4] = -1 end,
    function() ped = 0 end, -- 10: invalid ped resets, nothing sent
    function() ped = 1 end, -- 11: ped back, identical outfit re-emits (reset)
    function() model = 999 end, -- 12: same handle, model swap re-emits
    function() end, -- 13: unchanged
    function() ped = 2 end, -- 14: ped swap re-emits an identical outfit
    function() end, -- 15: unchanged
    function() eyeColor = 9 end, -- 16: feature-only change re-reports
    function() blendOk = false end,
    function() textures[4] = 1 end,
    function() blendOk = true end,
    function() overlay.value = 255 end,
    function() overlayFound = false end,
    function()
        overlayFound = true; overlay.value = 10; overlay.opacity = 1.2
        blendValues[57] = -0.2
    end,
    function() ped = 3; blendOk = false end,
    function() blendOk = true end,
    function() model = 500; blendOk = false end,
    function() end, -- 26: still down, nothing changed -> nothing resent
    function() blendOk = true; eyeColor = 65535; hairColor = -1 end,
    function() blendValues[25] = 205; drawables[5] = 3 end,
}

function CreateThread(callback) thread = callback end

function Wait(ms)
    assert(ms == Config.AppearancePollIntervalMs)
    step = step + 1
    local mutation = mutations[step]
    if not mutation then error('done') end
    mutation()
end

function PlayerPedId() return ped end
function DoesEntityExist(entity) return entity ~= 0 end
function GetEntityModel() return model end
function GetPedDrawableVariation(_, componentId) return drawables[componentId] or 0 end
function GetPedTextureVariation(_, componentId) return textures[componentId] or 0 end
function GetPedPropIndex(_, propId) return propDrawables[propId] end
function GetPedPropTextureIndex(_, propId) return propTextures[propId] or 0 end
function GetPedHairColor(entity) assert(entity == ped) return hairColor end
function GetPedHairHighlightColor(entity) assert(entity == ped) return hairHighlight end
function GetPedEyeColor(entity) assert(entity == ped) return eyeColor end

function GetPedHeadOverlayData(entity, index)
    assert(entity == ped and index == 1) -- beard overlay only
    if not overlayFound then return false, 0, 0, 0, 0, 0.0 end
    return true, overlay.value, overlay.colourType, overlay.firstColour,
        overlay.secondColour, overlay.opacity
end
function string.blob(length)
    assert(length == 80)
    return ('\0'):rep(length)
end
function string.blob_unpack(buffer, position, code)
    assert(#buffer == 80)
    assert(code == '<i4' or code == '<f')
    return assert(blendValues[position])
end
Citizen = {
    ReturnResultAnyway = function() return 0 end,
    InvokeNative = function(hash, entity, buffer, resultFlag)
        assert(hash == 0x2746BD9D88C5C5D0 and entity == ped)
        assert(type(buffer) == 'string' and #buffer == 80)
        assert(resultFlag == 0)
        return blendOk
    end,
}

function TriggerServerEvent(name, components, props, features, ...)
    assert(name == 'humalike:npc:appearanceChanged')
    assert(select('#', ...) == 0) -- nothing beyond features; model stays server-derived
    sent[#sent + 1] = { components = components, props = props, features = features }
end

dofile('client/appearance.lua')
pcall(thread)
assert(#sent == 18)
for _, report in ipairs(sent) do
    assert(#report.components == 12)
    for index, entry in ipairs(report.components) do
        assert(#entry == 3 and entry[1] == index - 1)
    end
end
assert(sent[1].components[5][2] == 0 and sent[1].components[5][3] == 0)
assert(#sent[1].props == 0) -- nothing equipped, empty props
local expected = { 21, 2, 3, 5, 255, 10, 8, 3, 4 }
assert(#sent[1].features == 9)
for index, value in ipairs(sent[1].features) do
    assert(value % 1 == 0 and value >= 0)
    assert(value == expected[index])
end
for report = 1, 8 do -- head blend readable throughout ticks 1..15
    assert(sent[report].features and #sent[report].features == 9)
end

assert(sent[2].components[5][1] == 4 and sent[2].components[5][2] == 7
    and sent[2].components[5][3] == 2)
assert(#sent[2].props == 0)
assert(#sent[3].props == 2)
assert(sent[3].props[1][1] == 0 and sent[3].props[1][2] == 13 and sent[3].props[1][3] == 0)
assert(sent[3].props[2][1] == 7 and sent[3].props[2][2] == 2 and sent[3].props[2][3] == 0)
assert(#sent[4].props == 2 and sent[4].props[1][3] == 3)
assert(sent[5].components[5][1] == 4 and sent[5].components[5][2] == 7
    and sent[5].components[5][3] == 0)
assert(#sent[5].props == 2)
assert(#sent[6].props == 2 and sent[6].components[5][2] == 7)
assert(#sent[7].props == 2 and sent[7].components[5][2] == 7)
assert(#sent[8].props == 2 and sent[8].components[5][2] == 7)
assert(sent[9].components[5][2] == 7 and sent[9].components[5][3] == 0)
assert(sent[9].features[9] == 9)
assert(sent[10].features == nil)
assert(sent[10].components[5][3] == 1)
assert(sent[11].features[6] == 0 and sent[11].features[7] == 0)
assert(sent[11].features[8] == 3 and sent[11].features[9] == 9)
assert(sent[12].features[6] == 0 and sent[12].features[7] == 0
    and sent[12].features[8] == 0)
assert(sent[13].features[3] == 0 and sent[13].features[6] == 10
    and sent[13].features[7] == 10 and sent[13].features[8] == 3)
assert(sent[14].features == false and #sent[14].props == 2)
assert(#sent[15].features == 9)
for index, value in ipairs({ 21, 2, 0, 5, 255, 10, 10, 3, 9 }) do
    assert(sent[15].features[index] == value)
end
assert(sent[16].features == false)
assert(sent[16].components[5][2] == 7) -- clothing still rides the report
assert(#sent[17].features == 9)
assert(sent[17].features[9] == 255) -- 65535 eye -> unknown
assert(sent[17].features[4] == 255) -- -1 hair -> unknown
assert(sent[18].features == false)
assert(sent[18].components[6][2] == 3)
