-- The edge frame is built from the tracker's cache: no native per NPC, a
-- hand-encoded message, deltas between keyframes, a keep-alive for the edge's
-- player timeout.
local callbacks, handlers, nuiMessages, rawMessages, serverEvents = {}, {}, {}, {}, {}

WorldConfig = {
    collector = { movementThreshold = 0.08 },
    npcEdge = {
        enabled = true, reportRadius = 150.0, maxNpcsPerFrame = 32,
        frameIntervalMs = 200, ticketRetryMs = 3000,
    },
}
HumalikeWorldCollector = { bootId = 'boot', latest = nil }
HumalikeWorldRegistry = { entries = {}, revision = 0 }

local function track(npcId, fields)
    local entry = {
        npcId = npcId, entity = fields.entity or 1, entityId = fields.entityId or 100,
        networkId = fields.networkId or 200, modelHash = fields.modelHash or 7,
        runtimeToken = fields.runtimeToken or 'tok', kind = fields.kind or 'persistent',
        activity = fields.activity or 'idle', generation = 1,
    }
    return {
        npcId = npcId, entry = entry, ped = entry.entity, generation = 1,
        version = fields.version or 1, exists = fields.exists ~= false,
        x = fields.x or 0.0, y = fields.y or 0.0, z = fields.z or 0.0,
        dist2 = fields.dist2 or 1.0, speed = fields.speed or 0.0,
        identityOk = fields.identityOk ~= false, heading = fields.heading or 45.0,
        zone = fields.zone, vehicleState = fields.vehicleState, ownVehicle = fields.ownVehicle,
    }
end
HumalikeWorldTrack = { tracks = {}, changeRevision = 0 }
local function changed() HumalikeWorldTrack.changeRevision = HumalikeWorldTrack.changeRevision + 1 end

function GetEntityModel() error('the frame never asks the game about an NPC') end
function GetEntityCoords() error('the frame never asks the game about an NPC') end
function RegisterNetEvent(name, callback) handlers[name] = callback end
function RegisterNUICallback(name, callback) callbacks[name] = callback end
function AddEventHandler() end
function CreateThread() end
function SetTimeout() end
function TriggerServerEvent(name, ...)
    serverEvents[#serverEvents + 1] = { name = name, args = { ... } }
end
function TriggerEvent() end
function SendNUIMessage(message) nuiMessages[#nuiMessages + 1] = message end
function SendNuiMessage(message) rawMessages[#rawMessages + 1] = message end
function PlayerPedId() return 1 end

dofile('client/npc_edge.lua')

HumalikeWorldTrack.tracks['npc-a'] = track('npc-a', { entity = 10, entityId = 110, networkId = 210, x = 5, dist2 = 25, zone = 'DOWNT' })
HumalikeWorldTrack.tracks['npc-b'] = track('npc-b', { entity = 20, entityId = 120, networkId = 220, x = 10, dist2 = 100, activity = 'talking',
    runtimeToken = 'quote"back\\slash', vehicleState = { network_id = 501, seat = 0, kind = 'bike' },
    ownVehicle = { network_id = 501, distance_m = 0.0, in_reach = true, kind = 'bike' } })
HumalikeWorldTrack.tracks['npc-far'] = track('npc-far', { entity = 30, entityId = 130, networkId = 230, x = 200, dist2 = 200 * 200 })
HumalikeWorldTrack.tracks['npc-gone'] = track('npc-gone', { entity = 40, entityId = 140, networkId = 240, exists = false })
HumalikeWorldTrack.tracks['npc-other'] = track('npc-other', { entity = 50, entityId = 150, networkId = 250, identityOk = false })

local player = { position = { x = 1.5, y = 2.25, z = 3.125 }, effectiveVoiceDistance = 15.0,
    vehicle = { networkId = 999, seat = -1, kind = 'car' } }

local message = HumalikeWorldNpcEdge.Frame(player, 1000)
assert(message, 'the first frame always goes out')
assert(message:find('"type":"npc_edge_frame","frame":{"type":"positions","sequence":1,', 1, true))
assert(message:find('"player":{"x":1.500,"y":2.250,"z":3.125,"effective_voice_distance":15.00,"vehicle":{"network_id":999,"seat":-1,"kind":"car"}}', 1, true))
assert(message:find('{"npc_id":"npc-b","entity_id":120,"network_id":220,"model_hash":7,"runtime_token":"quote\\"back\\\\slash","x":10.000,"y":0.000,"z":0.000,"heading":45.00,"vehicle":{"network_id":501,"seat":0,"kind":"bike"},"own_vehicle":{"network_id":501,"distance_m":0.00,"in_reach":true,"kind":"bike"}}', 1, true),
    'strings are escaped, vehicle and own vehicle ride along')
assert(message:find('"npc_id":"npc-a"', 1, true) and message:find('"zone_code":"DOWNT"', 1, true))
assert(message:find('"npc_id":"npc-b"', 1, true) < message:find('"npc_id":"npc-a"', 1, true), 'the talking NPC comes first')
assert(not message:find('npc-far', 1, true), 'out of the report radius')
assert(not message:find('npc-gone', 1, true) and not message:find('npc-other', 1, true),
    'a deleted ped or a handle that is not this NPC is never reported')
local _, commas = message:gsub('"npc_id"', '')
assert(commas == 2)

-- Nothing changed: no frame until the keep-alive, then a player-only frame.
assert(HumalikeWorldNpcEdge.Frame(player, 1200) == nil, 'a still scene sends nothing')
assert(HumalikeWorldNpcEdge.Frame(player, 1800) == nil)
message = HumalikeWorldNpcEdge.Frame(player, 2000)
assert(message and message:find('"sequence":2,', 1, true) and message:find('"npcs":[]}}', 1, true),
    'the keep-alive carries the player only')

-- A moved NPC is a delta of one.
HumalikeWorldTrack.tracks['npc-a'].x = 6.0
HumalikeWorldTrack.tracks['npc-a'].version = 2
message = HumalikeWorldNpcEdge.Frame(player, 2200)
assert(message == nil, 'a version bump the tracker did not announce is not seen: no walk over the tracks')
changed()
message = HumalikeWorldNpcEdge.Frame(player, 2200)
assert(message and message:find('"npc_id":"npc-a"', 1, true) and not message:find('"npc_id":"npc-b"', 1, true),
    'only the NPC that changed is in the delta')
assert(HumalikeWorldNpcEdge.Frame(player, 2400) == nil, 'and not again while it stays put')

-- The player moving sends a frame; a step of ten centimetres is the threshold.
player.position = { x = 1.55, y = 2.25, z = 3.125 }
assert(HumalikeWorldNpcEdge.Frame(player, 2600) == nil, 'five centimetres is noise')
player.position = { x = 1.75, y = 2.25, z = 3.125 }
message = HumalikeWorldNpcEdge.Frame(player, 2800)
assert(message and message:find('"x":1.750', 1, true) and message:find('"npcs":[]}}', 1, true))

-- The keyframe re-sends every reportable NPC.
message = HumalikeWorldNpcEdge.Frame(player, 3000)
local _, both = message:gsub('"npc_id"', '')
assert(both == 2, 'two seconds after the last keyframe everything goes out again')

-- A fresh socket starts from a keyframe.
callbacks['npcEdgeReady'](nil, function() end)
message = HumalikeWorldNpcEdge.Frame(player, 3200)
_, both = message:gsub('"npc_id"', '')
assert(both == 2 and HumalikeWorldNpcEdge.connected)

-- More NPCs than the cap rotate through the regular ones; urgent ones always go.
WorldConfig.npcEdge.maxNpcsPerFrame = 3
for index = 1, 5 do
    local npcId = ('npc-crowd-%d'):format(index)
    HumalikeWorldTrack.tracks[npcId] = track(npcId, { entity = 1000 + index, entityId = 2000 + index,
        networkId = 1200 + index, x = 50, dist2 = 50 * 50 })
end
changed()
HumalikeWorldNpcEdge.cursor = 1
local selected = HumalikeWorldNpcEdge.Select(true)
assert(#selected == 3 and selected[1].npcId == 'npc-b', 'the talking NPC leads a capped keyframe')
local seen = {}
for _ = 1, 6 do
    for _, item in ipairs(HumalikeWorldNpcEdge.Select(true)) do seen[item.npcId] = true end
end
local names = 0
for _ in pairs(seen) do names = names + 1 end
assert(names == 7, 'every reportable NPC is reached over a few frames')

HumalikeWorldNpcEdge.connected = true
HumalikeWorldNpcEdge.ticketPending = true
handlers['humalike:world:npcEdgeReconnect']()
assert(not HumalikeWorldNpcEdge.connected and HumalikeWorldNpcEdge.ticketPending,
    'edge reassignment must invalidate the active client connection')
assert(nuiMessages[#nuiMessages].type == 'npc_edge_disconnect',
    'edge reassignment must close only the edge NUI transport')
assert(serverEvents[#serverEvents].name == 'humalike:world:requestNpcEdgeTicket',
    'edge reassignment must request a fresh ticket immediately')
assert(#rawMessages == 0, 'the frame thread, not the decision, sends to the NUI')
print('client_npc_edge: ok')
