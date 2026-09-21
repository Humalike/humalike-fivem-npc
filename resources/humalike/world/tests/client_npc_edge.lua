local callbacks, handlers, threads, nuiMessages, serverEvents = {}, {}, {}, {}, {}
local coordsCalls, velocityCalls = {}, {}

WorldConfig = {
    collector = { movementThreshold = 0.08 },
    npcEdge = {
        enabled = true, reportRadius = 150.0, maxNpcsPerFrame = 32,
        frameIntervalMs = 200, ticketRetryMs = 3000,
    },
}
HumalikeWorldRegistry = { entries = {
    ['npc-a'] = {
        npcId = 'npc-a', entity = 10, entityId = 110, networkId = 210,
        modelHash = 100, runtimeToken = 'a', activity = 'idle', kind = 'persistent',
    },
    ['npc-b'] = {
        npcId = 'npc-b', entity = 20, entityId = 120, networkId = 220,
        modelHash = 200, runtimeToken = 'b', activity = 'talking', kind = 'persistent',
    },
    ['npc-stale'] = {
        npcId = 'npc-stale', entity = 30, entityId = 130, networkId = 230,
        modelHash = 300, runtimeToken = 'stale', activity = 'idle', kind = 'ambient',
    },
} }
HumalikeWorldVehicle = { StreamState = function() return nil end, OwnState = function() return nil end }
HumalikeWorldCollector = { bootId = 'boot', latest = nil }

function vector3(x, y, z) return { x = x, y = y, z = z } end
function DoesEntityExist() return true end
function GetEntityCoords(entity)
    coordsCalls[entity] = (coordsCalls[entity] or 0) + 1
    return entity == 10 and vector3(5, 0, 0) or vector3(10, 0, 0)
end
function GetEntityVelocity(entity)
    velocityCalls[entity] = (velocityCalls[entity] or 0) + 1
    return entity == 10 and vector3(0, 0, 0) or vector3(1, 0, 0)
end
function GetEntityHeading() return 90 end
function GetNameOfZone() return 'TEST' end
function NetworkGetNetworkIdFromEntity(entity) return entity + 200 end
function NetworkGetEntityIsNetworked() return true end
function NetworkDoesEntityExistWithNetworkId() return true end
function NetworkGetEntityFromNetworkId(networkId)
    return networkId == 230 and 99 or networkId - 200
end
function Entity(entity)
    return { state = { humalike_npc_id = entity == 30 and 'npc-stale' or nil } }
end
function GetEntityModel() return 999 end
function RegisterNetEvent(name, callback) handlers[name] = callback end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function AddEventHandler() end
function CreateThread(callback) threads[#threads + 1] = callback end
function SetTimeout() end
function TriggerServerEvent(name, ...)
    serverEvents[#serverEvents + 1] = { name = name, args = { ... } }
end
function TriggerEvent() end
function SendNUIMessage(message) nuiMessages[#nuiMessages + 1] = message end
function PlayerPedId() return 1 end

dofile('client/npc_edge.lua')

local frame = HumalikeWorldNpcEdge.BuildPositionsFrame({
    position = vector3(0, 0, 0), effectiveVoiceDistance = 15,
}, 1, 1)

assert(#frame.npcs == 2)
assert(coordsCalls[10] == 1 and coordsCalls[20] == 1,
    'each NPC position must be sampled once per frame')
assert(velocityCalls[10] == 1 and velocityCalls[20] == 1,
    'sort/priority must use cached velocity')
assert(frame.npcs[1].npc_id == 'npc-b', 'talking NPC must remain urgent')

HumalikeWorldNpcEdge.connected = true
HumalikeWorldNpcEdge.ticketPending = true
handlers['humalike:world:npcEdgeReconnect']()
assert(not HumalikeWorldNpcEdge.connected and HumalikeWorldNpcEdge.ticketPending,
    'edge reassignment must invalidate the active client connection')
assert(nuiMessages[#nuiMessages].type == 'npc_edge_disconnect',
    'edge reassignment must close only the edge NUI transport')
assert(serverEvents[#serverEvents].name == 'humalike:world:requestNpcEdgeTicket',
    'edge reassignment must request a fresh ticket immediately')
print('client_npc_edge: ok')
