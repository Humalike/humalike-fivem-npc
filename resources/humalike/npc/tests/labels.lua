Config = {
    NpcLabels = {
        Enabled = true,
        MaxDistance = 14,
        Height = 0.98,
        Scale = 1.0,
        DefaultLanguage = 'pl',
        ShowDefaultLanguage = false,
        LanguageLabels = { pl = 'pl', en = 'en', de = 'de', es = 'es', fr = 'fr' },
    },
}

LoadedPeds = { static = 1, far = 2 }
KnownNpcs = {
    static = { language = 'en-GB', voice_muted = true },
    far = { language = 'de', voice_muted = false },
}
AmbientPeds = { duplicate = 1, ambient = 3 }
AmbientNpcEntries = {
    duplicate = { language = 'fr', voice_muted = false },
    ambient = { language = 'pl-PL', voice_muted = false },
}

local thread
function CreateThread(callback) thread = callback end
function AddEventHandler() end
function DoesEntityExist() return true end
function GetGameplayCamCoord() return { x = 0, y = -2, z = 0 } end
function GetEntityCoords(ped)
    if ped == 2 then return { x = 30, y = 0, z = 0 } end
    if ped == 3 then return { x = 1, y = 0, z = 0 } end
    return { x = 0, y = 0, z = 0 }
end
function GetPedBoneCoords() error('labels must never follow a ped bone') end
function World3dToScreen2d(x, _, z)
    assert(z == 0.98, 'projection uses entity root plus stable height')
    return true, 0.5 + x * 0.01, 0.4
end

dofile('client/labels.lua')

assert(type(thread) == 'function', 'label runtime thread is registered')
assert(HumaLikeNpcLabels.NormalizeLanguage('pl') == false)
assert(HumaLikeNpcLabels.NormalizeLanguage('pl-PL') == false)
assert(HumaLikeNpcLabels.NormalizeLanguage('en-GB') == 'en')
assert(HumaLikeNpcLabels.NormalizeLanguage('it-IT') == 'it')

local frame, nearby = HumaLikeNpcLabels.BuildFrame()
assert(nearby == true)
assert(#frame == 2, 'all nearby unique AI peds are projected without a visible limit')
assert(frame[1][1] == 0.5 and frame[1][2] == 0.4)
assert(frame[1][3] == 'en' and frame[1][4] == 1)
assert(frame[2][3] == false and frame[2][4] == 0)

HumalikeNpcDirectTargets = {
    IsReady = function(npcId) return npcId == 'static' end,
    IsExclusive = function() return true end,
}
frame = HumaLikeNpcLabels.BuildFrame()
assert(frame[1][4] == 0, 'a capability-backed direct target is not shown as muted')
assert(frame[2][4] == 1, 'non-target NPCs are shown as muted during exclusive routing')

Config.NpcLabels.MaxDistance = 1.0
frame, nearby = HumaLikeNpcLabels.BuildFrame()
assert(#frame == 0 and nearby == false, 'squared-distance culling excludes distant peds')
