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
function CreateThread() end
function AddEventHandler() end
function DoesEntityExist() count('DoesEntityExist') return true end
local camera = { x = 0, y = -2, z = 0 }
local cameraRot = { x = 0.0, y = 0.0, z = 0.0 }
function GetGameplayCamCoord() count('GetGameplayCamCoord') return camera end
function GetGameplayCamRot() count('GetGameplayCamRot') return cameraRot end
local cameraFov = 50.0
function GetFinalRenderedCamFov() count('GetFinalRenderedCamFov') return cameraFov end
local positions = { [1] = { x = 0, y = 0, z = 0 }, [2] = { x = 30, y = 0, z = 0 }, [3] = { x = 1, y = 0, z = 0 } }
function GetEntityCoords(ped) count('GetEntityCoords') return positions[ped] end
function GetPedBoneCoords() error('labels must never follow a ped bone') end
function World3dToScreen2d(x, _, z)
    count('World3dToScreen2d')
    assert(z == 0.98, 'projection uses entity root plus stable height')
    return true, 0.5 + x * 0.01, 0.4
end

local function trackOf(ped, dist)
    local at = positions[ped]
    return { ped = ped, exists = true, dist2 = dist * dist, speed = 0.0, x = at.x, y = at.y, z = at.z }
end
HumalikeWorldTrack = { tracks = {
    static = trackOf(1, 0), far = trackOf(2, 30), duplicate = trackOf(1, 0), ambient = trackOf(3, 1),
} }

dofile('../world/client/pulse.lua')
dofile('client/labels.lua')

assert(type(HumaLikeNpcLabels.Render) == 'function', 'the label loop is a job of the shared pulse')
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
function SendNUIMessage() error('label messages are written by hand') end
function SendNuiMessage(raw)
    local _, count = raw:gsub('%[[%d%.]+,[%d%.]+,', '')
    sent[#sent + 1] = { type = raw:match('"type":"([^"]+)"'), raw = raw, count = count }
end
local sleep
local function tick(at)
    now = at
    sleep = HumalikePulse.Run(now)
end
natives = {}
for index = 1, 6 do tick(index * 16) end -- six game frames at 60 fps
assert(#sent == 1 and sent[1].type == 'labels:frame', 'a still scene is sent to the NUI once')
assert(sent[1].count == 2 and sent[1].raw:find(',"static"]', 1, true) and sent[1].raw:find(',"ambient"]', 1, true),
    'both labels carry their npc id')
assert(sent[1].raw == HumaLikeNpcLabels.EncodeFrame({ { 0.5, 0.4, 'en', 0, 'static' }, { 0.51, 0.4, false, 1, 'ambient' } }, 1.0)
    or sent[1].raw == HumaLikeNpcLabels.EncodeFrame({ { 0.51, 0.4, false, 1, 'ambient' }, { 0.5, 0.4, 'en', 0, 'static' } }, 1.0),
    'the frame is the hand-encoded tuple list')
assert(HumaLikeNpcLabels.EncodeFrame({ { 0.5, 0.4, 'en', 1, 'a"b' } }, 1.0)
    == '{"type":"labels:frame","scale":1.000,"labels":[[0.5000,0.4000,"en",1,"a\\"b"]]}')
assert(natives.World3dToScreen2d == 2, 'a still camera over still NPCs projects each label once')
assert(natives.GetGameplayCamRot == 3 and natives.GetGameplayCamCoord == 3,
    'the render job runs at the configured 30 fps: three renders in six game frames')
assert(sleep == 3, 'the pulse sleeps until the next render is due, on the 33 ms grid')
tick(990)
assert(#sent == 1, 'nothing more within the same second')
tick(1023)
assert(#sent == 2, 'and repeated on every heartbeat of the pulse so the NUI keeps it')
natives = {}
cameraRot = { x = 0.0, y = 0.0, z = 5.0 }
tick(1056)
assert(natives.World3dToScreen2d == 2, 'a turned camera projects again')
assert(#sent == 2, 'to the same screen spot: nothing to send')
HumalikeWorldTrack.tracks.ambient.speed = 1.2
positions[3] = { x = 2, y = 0, z = 0 }
natives = {}
tick(1089)
assert(natives.GetEntityCoords == 1 and natives.World3dToScreen2d == 1 and natives.DoesEntityExist == nil,
    'a walking NPC is read from the game and projected; the still one is not, and nobody is asked whether it exists')
assert(#sent == 3, 'a label that moved is sent at once')
tick(1122)
assert(#sent == 3, 'and not again while it stays put')
HumalikeWorldTrack.tracks.ambient.speed = 0.0
tick(1155)
natives = {}
cameraFov = 20.0
tick(1188)
assert(natives.World3dToScreen2d == 2, 'a zoom moves every label on screen: both are projected again')
cameraFov = 50.0

positions[3] = { x = 0, y = 0, z = 0 }
camera = { x = 500, y = -2, z = 0 }
HumalikeWorldTrack.tracks.static.x = 500
tick(1221)
assert(sent[#sent].type == 'labels:frame' and sent[#sent].count == 1 and sent[#sent].raw:find(',"static"]', 1, true),
    'only the ped that is still there keeps its label')
positions[3] = { x = 2, y = 0, z = 0 }
camera = { x = 0, y = -2, z = 0 }
HumalikeWorldTrack.tracks.static.x = 0

HumalikeWorldTrack.tracks = {}
LoadedPeds, AmbientPeds = {}, {}
function World3dToScreen2d() error('nothing to project without a nearby NPC') end
tick(3000)
assert(sent[#sent].type == 'labels:clear' and sent[#sent].raw == '{"type":"labels:clear"}' and sleep == 250,
    'labels go away and the job sleeps')
local cleared = #sent
natives = {}
tick(3250)
tick(3500)
assert(#sent == cleared and sleep == 250 and natives.GetGameplayCamCoord == nil,
    'an empty street costs one candidate scan per 250 ms and no native')

LoadedPeds = { fresh = 9 }
KnownNpcs.fresh = { language = 'de' }
positions[9] = { x = 0, y = 0, z = 0 }
function World3dToScreen2d() return true, 0.5, 0.5 end
natives = {}
tick(4000)
assert(natives.GetEntityCoords == 2 and sent[#sent].type == 'labels:frame' and sent[#sent].raw:find(',"fresh"]', 1, true),
    'an unregistered ped costs one coordinate read to find and one to project')

Config.NpcLabels.Enabled = false
tick(4033)
assert(sent[#sent].type == 'labels:clear' and sleep == 967, 'next look on the second')
print('labels: ok')
