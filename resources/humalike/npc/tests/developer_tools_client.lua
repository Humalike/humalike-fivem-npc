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
function DoesEntityExist(entity) return entity == 99 or entity == 98 end
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
local bagReads, spawnIds = 0, { [99] = 'debug-1' }
function Entity(ped)
    return { state = setmetatable({}, { __index = function(_, key)
        assert(key == 'humalike_debug_spawn_id')
        bagReads = bagReads + 1
        return spawnIds[ped]
    end }) }
end
local bagHandlers = {}
function AddStateBagChangeHandler(key, _, handler) bagHandlers[key] = handler end
function GetEntityFromStateBagName(name) return tonumber(name:match('^entity:(%d+)$')) end
function print(message) consoleReply = message end

dofile('client/developer_tools.lua')

assert(localEvents[1][1] == 'chat:addSuggestion')
assert(localEvents[1][2] == '/humalike_dev')
assert(#localEvents[1][4] == 3)

handlers['humalike:npc:developerReply']('[humalike-dev] spawned')
assert(consoleReply == '[humalike-dev] spawned')

handlers['humalike:npc:ambientPedAssigned']('npc-id', 99)
assert(#threads == 1 and bagReads == 1, 'a ped the developer tools spawned is watched, after one bag read')
threads[1]()
assert(wandered == 99)

handlers['humalike:npc:ambientPedAssigned']('npc-plain', 98)
assert(#threads == 1 and bagReads == 2, 'no spawn id, nothing to watch')
handlers['humalike:npc:ambientPedAssigned']('npc-id', 99)
assert(#threads == 1 and bagReads == 3)
AmbientPedNpcIds = { [98] = 'npc-plain' }
bagHandlers.humalike_debug_spawn_id('entity:98', 'humalike_debug_spawn_id', 'debug-2')
assert(#threads == 2 and bagReads == 3, 'the handler brings the value: no read')
wandered = nil
threads[2]()
assert(wandered == 98)
bagHandlers.humalike_debug_spawn_id('entity:97', 'humalike_debug_spawn_id', 'debug-3')
assert(#threads == 2, 'a ped this client holds no lease on is not its business')

handlers['humalike:npc:developerGotoAmbient'](55)
assert(teleported[1] == 1 and teleported[2] == 2 and teleported[3] == 3)
