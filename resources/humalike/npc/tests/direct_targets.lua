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

handlers['humalike:world:listener']({ forward = { x = 1, y = 0, z = 0 } })
assert(#latest == 3, 'follower, vehicle peer and close gaze target are selected')
assert(latest[1] == 'follower' and latest[2] == 'vehicle' and latest[3] == 'gaze')
assert(notifications == 2)

timer = timer + 100
handlers['humalike:world:listener']({ forward = { x = 1, y = 0, z = 0 } })
assert(notifications == 2, 'unchanged targets are not republished')

HumalikeNpcDirectTargets.SetAvailable(true)
assert(HumalikeNpcDirectTargets.IsExclusive())
assert(HumalikeNpcDirectTargets.IsReady('gaze'))
HumalikeNpcDirectTargets.Lock()
playerVehicle = 0
positions[3] = { x = 0, y = 3, z = 0 }
timer = timer + 100
handlers['humalike:world:listener']({ forward = { x = 1, y = 0, z = 0 } })
assert(#HumalikeNpcDirectTargets.Get() == 3, 'targets stay frozen during PTT')
HumalikeNpcDirectTargets.Unlock()
latest = HumalikeNpcDirectTargets.Get()
assert(#latest == 2 and latest[1] == 'follower' and latest[2] == 'far',
    'unlock publishes the follower and nearest gaze target within three metres of the player')

HumalikeNpcDirectTargets.SetAvailable(false)
assert(not HumalikeNpcDirectTargets.IsExclusive())
assert(not HumalikeNpcDirectTargets.IsReady('follower'), 'UI readiness is capability gated')
print('direct_targets: ok')
