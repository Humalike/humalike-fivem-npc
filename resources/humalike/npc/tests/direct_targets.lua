-- Direct voice targets are chosen from the tracker's cache; the game is asked
-- about the player, the camera, and the line of sight to one gaze target.
local handlers = {}
local timer = 100
local natives = {}
local function count(name) natives[name] = (natives[name] or 0) + 1 end
local positions = {
    [100] = { x = 1, y = 0, z = 0 },
    [1] = { x = 0, y = 2, z = 0 },
    [2] = { x = 0, y = -2, z = 0 },
    [3] = { x = 2, y = 0, z = 0 },
    [4] = { x = 4, y = 0, z = 0 },
    [5] = { x = 0, y = 1, z = 0 },
}
ActionControlledPeds = { [1] = 'follow_player', [5] = 'follow_player' }
ActionParams = { [1] = { player_id = 7 }, [5] = { player_id = 8 } }

local function track(npcId, ped, vehicleNet)
    local at = positions[ped]
    return {
        npcId = npcId, ped = ped, exists = true, x = at.x, y = at.y, z = at.z, speed = 0.0,
        vehicleState = vehicleNet and { network_id = vehicleNet, seat = 0, kind = 'car' } or nil,
    }
end
HumalikeWorldTrack = { tracks = {
    follower = track('follower', 1),
    vehicle = track('vehicle', 2, 50),
    gaze = track('gaze', 3),
    far = track('far', 4),
    other_follower = track('other_follower', 5),
} }
HumalikeWorldCollector = { latest = { vehicle = { networkId = 50, seat = -1 } } }

function AddEventHandler(name, callback) handlers[name] = callback end
function CreateThread() end
function GetGameTimer() return timer end
function PlayerId() return 0 end
function PlayerPedId() count('PlayerPedId') return 100 end
function GetPlayerServerId() count('GetPlayerServerId') return 7 end
function GetGameplayCamCoord() count('GetGameplayCamCoord') return { x = -1, y = 0, z = 0 } end
function GetEntityCoords(ped) count('GetEntityCoords') assert(ped == 100, 'only the player is read from the game') return positions[ped] end
function IsEntityDead(ped) count('IsEntityDead') return false end
function GetVehiclePedIsIn() error('seats come from the tracker and the collector') end
function HasEntityClearLosToEntity(_, ped) count('HasEntityClearLosToEntity') return ped ~= 6 end
dofile('../world/client/pulse.lua')
dofile('client/direct_targets.lua')

local notifications = 0
local latest
HumalikeNpcDirectTargets.Subscribe(function(values)
    notifications = notifications + 1
    latest = values
end)
assert(notifications == 1 and #latest == 0, 'subscriber receives the initial state')

HumalikeNpcDirectTargets.Refresh({ forward = { x = 1, y = 0, z = 0 } })
assert(#latest == 3, 'follower, vehicle peer and close gaze target are selected')
assert(latest[1] == 'follower' and latest[2] == 'vehicle' and latest[3] == 'gaze')
assert(notifications == 2)
assert(natives.GetEntityCoords == 1 and natives.GetGameplayCamCoord == 1 and natives.PlayerPedId == 1)
assert(natives.IsEntityDead == 3 and natives.HasEntityClearLosToEntity == 1,
    'only the three candidates are checked for life, one for line of sight')

timer = timer + 100
HumalikeNpcDirectTargets.Refresh({ forward = { x = 1, y = 0, z = 0 } })
assert(notifications == 2, 'unchanged targets are not republished')
assert(natives.GetPlayerServerId == 1, 'the session id is asked once')

HumalikeNpcDirectTargets.SetAvailable(true)
assert(HumalikeNpcDirectTargets.IsExclusive())
assert(HumalikeNpcDirectTargets.IsReady('gaze'))
HumalikeNpcDirectTargets.Lock()
HumalikeWorldCollector.latest.vehicle = nil
HumalikeWorldTrack.tracks.gaze.y = 3
HumalikeWorldTrack.tracks.gaze.x = 0
timer = timer + 100
HumalikeNpcDirectTargets.Refresh({ forward = { x = 1, y = 0, z = 0 } })
assert(#HumalikeNpcDirectTargets.Get() == 3, 'targets stay frozen during PTT')
HumalikeNpcDirectTargets.Unlock()
latest = HumalikeNpcDirectTargets.Get()
assert(#latest == 2 and latest[1] == 'follower' and latest[2] == 'far',
    'unlock publishes the follower and nearest gaze target within three metres of the player')

HumalikeNpcDirectTargets.SetAvailable(false)
assert(not HumalikeNpcDirectTargets.IsExclusive())
assert(not HumalikeNpcDirectTargets.IsReady('follower'), 'UI readiness is capability gated')

-- The refresh slows down while no NPC is within ten metres and nobody is a target.
ActionControlledPeds = {}
local forward = { forward = { x = 1, y = 0, z = 0 } }
assert(HumalikeNpcDirectTargets.Refresh(forward) == true, 'NPCs within ten metres keep the fast refresh')
for _, item in pairs(HumalikeWorldTrack.tracks) do item.x, item.y = 50 + item.ped, 0 end
assert(HumalikeNpcDirectTargets.Refresh(forward) == false, 'an empty street is idle')
ActionControlledPeds = { [1] = 'follow_player' }
assert(HumalikeNpcDirectTargets.Refresh(forward) == true, 'a far follower is still a target')
ActionControlledPeds = {}
assert(HumalikeNpcDirectTargets.Refresh(forward) == false and #HumalikeNpcDirectTargets.Get() == 0)
HumalikeWorldCollector.listener = forward
timer = 10000
assert(HumalikePulse.Run(timer) == 400, 'nothing nearby: the next refresh comes 400 ms later')
natives = {}
timer = 10200
HumalikePulse.Run(timer)
assert(natives.GetEntityCoords == nil, 'and nothing is read in between')
HumalikeWorldTrack.tracks.gaze.x, HumalikeWorldTrack.tracks.gaze.y = 4, 0
timer = 10400
assert(HumalikePulse.Run(timer) == 100, 'and the fast refresh is back once an NPC is near')

-- A dead gaze target is not a target; life is asked again after half a second.
HumalikeWorldTrack.tracks.gaze.x, HumalikeWorldTrack.tracks.gaze.y = 2, 0
function IsEntityDead(ped) return ped == 3 end
HumalikeNpcDirectTargets.Refresh(forward)
assert(#HumalikeNpcDirectTargets.Get() == 1, 'the cached answer holds for half a second')
timer = timer + 600
HumalikeNpcDirectTargets.Refresh(forward)
assert(#HumalikeNpcDirectTargets.Get() == 0)
natives = {}
timer = timer + 100
HumalikeNpcDirectTargets.Refresh(forward)
assert(natives.GetGameplayCamCoord == 1 and natives.HasEntityClearLosToEntity == nil,
    'with the gaze target dead no line of sight is traced; the camera is read for the candidate')
print('direct_targets: ok')
