
Config = { Wave = { DurationMs = 3000 } }

local ped = 1
local timeouts = {}
local anims = 0

function GetEntityCoords() return { x = 0 } end
function DoesEntityExist() return true end
function RequestAnimDict() end
function HasAnimDictLoaded() return true end
function TaskPlayAnim() anims = anims + 1 end
function SetTimeout(_ms, fn) timeouts[#timeouts + 1] = fn end
function CreateThread() end
function AddStateBagChangeHandler() end
function SetBlockingOfNonTemporaryEvents() end
function SetPedKeepTask() end
function Entity() return { state = { set = function() end } } end
function Wait() end
function GetActivePlayers() return {} end
function GetPlayerPed() return 0 end

dofile('client/reactions.lua')
dofile('client/actions/state.lua')
dofile('client/actions/wave.lua')
NpcActions['wave'](ped, {})
assert(anims == 1)
assert(IsActionControlled(ped), 'wave must own the ped while it plays')
timeouts[#timeouts]()
assert(not IsActionControlled(ped), 'wave must hand the ped back')
MarkActionControl(ped, 'follow_player', { player_id = 99 })
timeouts = {}
NpcActions['wave'](ped, {})
assert(anims == 2)
assert(#timeouts == 0, 'a borrowed-nothing wave schedules no release')
assert(ActionParams[ped].player_id == 99, 'wave must not steal the follow partner')
assert(ActionControlledPeds[ped] == 'follow_player')

print('wave: ok')
