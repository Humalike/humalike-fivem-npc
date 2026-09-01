local handlers = {}
local threads = {}
local wandered
local teleported
local consoleReply
local localEvents = {}

function RegisterNetEvent() end
function AddEventHandler(name, callback) handlers[name] = callback end
function TriggerEvent(...)
    localEvents[#localEvents + 1] = { ... }
end
function CreateThread(callback) threads[#threads + 1] = callback end
function DoesEntityExist(entity) return entity == 99 end
function GetGameTimer() return 100 end
function Wait() end
function NetworkHasControlOfEntity() return true end
function SetPedKeepTask() end
function TaskWanderStandard(ped) wandered = ped end
function NetworkDoesEntityExistWithNetworkId() return true end
function NetworkGetEntityFromNetworkId() return 99 end
function GetOffsetFromEntityInWorldCoords()
    return { x = 1, y = 2, z = 3 }
end
function RequestCollisionAtCoord() end
function PlayerPedId() return 7 end
function SetEntityCoordsNoOffset(_, x, y, z) teleported = { x, y, z } end
function GetCurrentResourceName() return 'humalike' end
function Entity()
    return { state = { humalike_debug_spawn_id = 'debug-1' } }
end
function print(message) consoleReply = message end

dofile('client/developer_tools.lua')

assert(localEvents[1][1] == 'chat:addSuggestion')
assert(localEvents[1][2] == '/humalike_dev')
assert(#localEvents[1][4] == 3)

handlers['humalike:npc:developerReply']('[humalike-dev] spawned')
assert(consoleReply == '[humalike-dev] spawned')

handlers['humalike:npc:ambientPedAssigned']('npc-id', 99)
assert(#threads == 1)
threads[1]()
assert(wandered == 99)

handlers['humalike:npc:developerGotoAmbient'](55)
assert(teleported[1] == 1 and teleported[2] == 2 and teleported[3] == 3)
