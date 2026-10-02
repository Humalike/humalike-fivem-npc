local handlers = {}
local timer = 100
local playerVehicle = 50
local positions = {
    [100] = { x = 1, y = 0, z = 0 },
    [1] = { x = 0, y = 2, z = 0 },
    [2] = { x = 0, y = -2, z = 0 },
    [3] = { x = 2, y = 0, z = 0 },
    [4] = { x = 4, y = 0, z = 0 },
    [5] = { x = 0, y = 1, z = 0 },
}
local vehicles = { [2] = 50 }
ActionControlledPeds = { [1] = 'follow_player', [5] = 'follow_player' }
ActionParams = { [1] = { player_id = 7 }, [5] = { player_id = 8 } }

HumalikeWorldRegistry = { entries = {
    follower = { entity = 1 },
    vehicle = { entity = 2 },
    gaze = { entity = 3 },
    far = { entity = 4 },
    other_follower = { entity = 5 },
} }

function AddEventHandler(name, callback) handlers[name] = callback end
local thread
function CreateThread(callback) thread = callback end
function GetGameTimer() return timer end
function PlayerId() return 0 end
function PlayerPedId() return 100 end
function GetPlayerServerId() return 7 end
function GetGameplayCamCoord() return { x = -1, y = 0, z = 0 } end
function DoesEntityExist() return true end
function IsEntityDead() return false end
function GetEntityCoords(ped) return positions[ped] end
function GetVehiclePedIsIn(ped)
    if ped == 100 then return playerVehicle end
    return vehicles[ped] or 0
end
function HasEntityClearLosToEntity(_, ped) return ped ~= 6 end
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

timer = timer + 100
HumalikeNpcDirectTargets.Refresh({ forward = { x = 1, y = 0, z = 0 } })
assert(notifications == 2, 'unchanged targets are not republished')

HumalikeNpcDirectTargets.SetAvailable(true)
assert(HumalikeNpcDirectTargets.IsExclusive())
assert(HumalikeNpcDirectTargets.IsReady('gaze'))
HumalikeNpcDirectTargets.Lock()
playerVehicle = 0
positions[3] = { x = 0, y = 3, z = 0 }
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
for ped in pairs(positions) do
    if ped ~= 100 then positions[ped] = { x = 50 + ped, y = 0, z = 0 } end
end
assert(HumalikeNpcDirectTargets.Refresh(forward) == false, 'an empty street is idle')
ActionControlledPeds = { [1] = 'follow_player' }
assert(HumalikeNpcDirectTargets.Refresh(forward) == true, 'a far follower is still a target')
ActionControlledPeds = {}
HumalikeWorldCollector = { listener = forward }
function Wait(ms) coroutine.yield(ms) end
local loop = coroutine.create(thread)
local _, waited = coroutine.resume(loop)
assert(waited == 100)
_, waited = coroutine.resume(loop)
assert(waited == 400, 'nothing nearby: the next refresh comes 400 ms later')
positions[3] = { x = 4, y = 0, z = 0 }
_, waited = coroutine.resume(loop)
assert(waited == 100, 'and the fast refresh is back once an NPC is near')
print('direct_targets: ok')
