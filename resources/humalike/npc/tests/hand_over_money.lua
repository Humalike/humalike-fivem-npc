
Config = { Robbery = { HandoverAnimMs = 1500 } }

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
function GetEntityFromStateBagName() return 0 end
function Entity() return { state = { set = function() end } } end
function Wait() end
function GetActivePlayers() return {} end
function GetPlayerPed() return 0 end
function IsEntityDead() return false end
function IsPedRagdoll() return false end
function NetworkHasControlOfEntity() return true end

dofile('client/reactions.lua')
dofile('client/actions/state.lua')
dofile('client/actions/hand_over_money.lua')
NpcActions['hand_over_money'](ped, {})
assert(anims == 1)
assert(IsActionControlled(ped), 'gesture owns the idle ped while it plays')
timeouts[#timeouts]()
assert(not IsActionControlled(ped), 'gesture hands the idle ped back')
MarkActionControl(ped, 'hands_up')
timeouts = {}
anims = 0
NpcActions['hand_over_money'](ped, {})
assert(anims == 1, 'gesture still plays over a held pose')
assert(ActionControlledPeds[ped] == 'hands_up', 'the underlying pose is untouched')
assert(#timeouts == 0, 'a ridden-over gesture schedules no hand-back')
assert(ActionControlledPeds[ped] == 'hands_up', 'pose still owns the ped after the gesture')

print('hand_over_money: ok')
