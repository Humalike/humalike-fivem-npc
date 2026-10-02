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

local natives = {}
local function count(name) natives[name] = (natives[name] or 0) + 1 end
local thread
function CreateThread(callback) thread = callback end
function AddEventHandler() end
function DoesEntityExist() count('DoesEntityExist') return true end
local camera = { x = 0, y = -2, z = 0 }
local cameraRot = { x = 0.0, y = 0.0, z = 0.0 }
function GetGameplayCamCoord() count('GetGameplayCamCoord') return camera end
function GetGameplayCamRot() count('GetGameplayCamRot') return cameraRot end
local positions = { [1] = { x = 0, y = 0, z = 0 }, [2] = { x = 30, y = 0, z = 0 }, [3] = { x = 1, y = 0, z = 0 } }
function GetEntityCoords(ped) count('GetEntityCoords') return positions[ped] end
function GetPedBoneCoords() error('labels must never follow a ped bone') end
function World3dToScreen2d(x, _, z)
    count('World3dToScreen2d')
    assert(z == 0.98, 'projection uses entity root plus stable height')
    return true, 0.5 + x * 0.01, 0.4
end

-- The tracker already knows where every registered NPC stands.
local function trackOf(ped, dist)
    local at = positions[ped]
    return { ped = ped, exists = true, dist2 = dist * dist, speed = 0.0, x = at.x, y = at.y, z = at.z }
end
HumalikeWorldTrack = { tracks = {
    static = trackOf(1, 0), far = trackOf(2, 30), duplicate = trackOf(1, 0), ambient = trackOf(3, 1),
} }

dofile('client/labels.lua')

assert(type(thread) == 'function', 'label runtime thread is registered')
assert(HumaLikeNpcLabels.NormalizeLanguage('pl') == false)
assert(HumaLikeNpcLabels.NormalizeLanguage('pl-PL') == false)
assert(HumaLikeNpcLabels.NormalizeLanguage('en-GB') == 'en')
assert(HumaLikeNpcLabels.NormalizeLanguage('it-IT') == 'it')
Config.NpcLabels.DefaultLanguage = nil
assert(HumaLikeNpcLabels.NormalizeLanguage('en') == false, 'English is the default main language')
assert(HumaLikeNpcLabels.NormalizeLanguage('pl') == 'pl')
Config.NpcLabels.DefaultLanguage = 'pl'

local frame, nearby = HumaLikeNpcLabels.BuildFrame()
assert(nearby == true)
assert(#frame == 2, 'all nearby unique AI peds are projected without a visible limit')
table.sort(frame, function(a, b) return a[5] < b[5] end)
assert(frame[1][5] == 'ambient' and frame[2][5] == 'static', 'each label names its NPC')
assert(frame[2][1] == 0.5 and frame[2][2] == 0.4)
assert(frame[2][3] == 'en' and frame[2][4] == 1)
assert(frame[1][3] == false and frame[1][4] == 0)
assert(natives.GetEntityCoords == nil, 'a still NPC is projected from the tracker\'s position')

HumalikeNpcDirectTargets = {
    IsReady = function(npcId) return npcId == 'static' end,
    IsExclusive = function() return true end,
}
frame = HumaLikeNpcLabels.BuildFrame()
table.sort(frame, function(a, b) return a[5] < b[5] end)
assert(frame[2][4] == 0, 'a capability-backed direct target is not shown as muted')
assert(frame[1][4] == 1, 'non-target NPCs are shown as muted during exclusive routing')

Config.NpcLabels.MaxDistance = 1.0
frame, nearby = HumaLikeNpcLabels.BuildFrame()
assert(#frame == 0 and nearby == false, 'squared-distance culling excludes distant peds')

Config.NpcLabels.MaxDistance = 14
local sent, now = {}, 0
function GetGameTimer() return now end
local waits = {}
function Wait(ms) waits[#waits + 1] = ms coroutine.yield() end
function SendNUIMessage(message) sent[#sent + 1] = message end
local loop = coroutine.create(thread)
local function tick(at)
    now = at
    assert(coroutine.resume(loop))
end
natives = {}
for index = 1, 6 do tick(index * 16) end -- six game frames at 60 fps
assert(#sent == 1 and sent[1].type == 'labels:frame', 'a still scene is sent to the NUI once')
assert(#sent[1].labels == 2 and #sent[1].labels[1] == 5)
assert(natives.World3dToScreen2d == 2, 'a still camera over still NPCs projects each label once')
assert(natives.GetGameplayCamRot == 3 and natives.GetGameplayCamCoord == 3,
    'the render loop runs at the configured 30 fps: three renders in six game frames')
assert(waits[1] == 17 and waits[2] == 1, 'between renders the thread sleeps out the interval')
tick(96 + 1000)
assert(#sent == 2, 'and repeated on the heartbeat so the NUI keeps it')
natives = {}
cameraRot = { x = 0.0, y = 0.0, z = 5.0 }
tick(96 + 1000 + 33)
assert(natives.World3dToScreen2d == 2, 'a turned camera projects again')
assert(#sent == 2, 'to the same screen spot: nothing to send')
HumalikeWorldTrack.tracks.ambient.speed = 1.2
positions[3] = { x = 2, y = 0, z = 0 }
natives = {}
tick(96 + 1000 + 66)
assert(natives.GetEntityCoords == 1 and natives.World3dToScreen2d == 1,
    'a walking NPC is read from the game and projected; the still one is not')
assert(#sent == 3, 'a label that moved is sent at once')
tick(96 + 1000 + 99)
assert(#sent == 3, 'and not again while it stays put')

-- Nobody within range: the scene is cleared once, then the thread only rechecks every 250 ms.
HumalikeWorldTrack.tracks = {}
LoadedPeds, AmbientPeds = {}, {}
function World3dToScreen2d() error('nothing to project without a nearby NPC') end
tick(3000)
assert(sent[#sent].type == 'labels:clear' and waits[#waits] == 250, 'labels go away and the thread sleeps')
local cleared = #sent
tick(3250)
tick(3500)
assert(#sent == cleared and waits[#waits] == 250, 'an empty street costs one candidate scan per 250 ms')

-- A ped the tracker does not know yet is still found, by asking the game.
LoadedPeds = { fresh = 9 }
KnownNpcs.fresh = { language = 'de' }
positions[9] = { x = 0, y = 0, z = 0 }
function World3dToScreen2d() return true, 0.5, 0.5 end
natives = {}
tick(4000)
assert(natives.GetEntityCoords == 2 and sent[#sent].type == 'labels:frame' and sent[#sent].labels[1][5] == 'fresh',
    'an unregistered ped costs one coordinate read to find and one to project')
print('labels: ok')
