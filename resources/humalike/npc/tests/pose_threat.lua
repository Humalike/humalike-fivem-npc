
local threads, posts = {}, {}
local now = 10000
local playerCoords = { ['7'] = { x = 0, y = 0, z = 0 } }
local armedByPed = {}
local liveEntities = { [101] = true, [700] = true }
local hashes = {}

local vectorMeta = {}
vectorMeta.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta)
end
vectorMeta.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end
local function at(coords) return vector3(coords.x, coords.y, coords.z) end

function CreateThread(handler) threads[#threads + 1] = handler end
function Wait() error('stop thread', 0) end
function SetTimeout() end
function GetGameTimer() return now end
function GetPlayers() return { '7' } end
function GetPlayerPed(playerId) return playerId == '7' and 700 or 0 end
function DoesEntityExist(entity) return liveEntities[entity] == true end
function GetEntityCoords(entity)
    if entity == 700 then return at(playerCoords['7']) end
    return at({ x = 0, y = 0, z = 0 })
end
local nextHash = 1000
function GetHashKey(name)
    if not hashes[name] then
        nextHash = nextHash + 1
        hashes[name] = nextHash
    end
    return hashes[name]
end
function GetSelectedPedWeapon(ped)
    return armedByPed[ped] and GetHashKey('WEAPON_PISTOL') or GetHashKey('WEAPON_UNARMED')
end
function Entity(entity)
    return { state = { set = function() end } }
end
function HumalikeDebug() end
function HumalikeReleasePose() return true end
HumalikePlayer = { IsCharacterLoaded = function() return true end }
HumalikeHttp = {
    PostAction = function(action, observation) posts[#posts + 1] = { action, observation } end,
    NextSourceEventId = function(playerId) return 'evt-' .. tostring(playerId) end,
}

Config = {
    PoseAbandonMs = 120000, PoseAbandonRadius = 60.0, PoseAbandonTickMs = 5000,
    PoseThreat = { Enabled = true, Radius = 30.0, ClearMs = 10000 },
    PoseThreatTickMs = 2500,
}
NpcRegistry = { ['static-1'] = { npc_id = 'static-1', entity_id = 101 } }
function ValidateAmbientActionTarget(target)
    if not liveEntities[target.entity_id] then return nil, nil, 'ambient_entity_unavailable' end
    return { npc_id = target.npc_id }, target.entity_id
end

dofile('server/pose_ledger.lua')
dofile('server/pose_threat.lua')

local staticTarget = { kind = 'static', npc_id = 'static-1' }
armedByPed[700] = true
RecordNpcPose('static-1', 'hands_up', staticTarget)
HumalikePoseThreatSweep()
now = now + 600000
HumalikePoseThreatSweep()
assert(#posts == 0, 'a scene with a weapon out is never all-clear')
armedByPed[700] = nil
now = now + 600000
HumalikePoseThreatSweep()
assert(#posts == 0, 'holstered but still standing there: the body stays kept')
playerCoords['7'] = { x = 31, y = 0, z = 0 }
HumalikePoseThreatSweep()
assert(#posts == 0, 'the window starts when they walk off, not retroactively')
now = now + 9000
HumalikePoseThreatSweep()
assert(#posts == 0, 'still inside the window')
now = now + 2000
HumalikePoseThreatSweep()
assert(#posts == 1, 'everyone gone for the window reaches the edge')
assert(posts[1][1] == 'ingest_world_event')
assert(posts[1][2].event.type == 'threat_subsided')
assert(posts[1][2].event.npc_id == 'static-1')
assert(posts[1][2].fivem_session_id == 7, 'attributed to the nearest witness, however far')
now = now + 60000
HumalikePoseThreatSweep()
assert(#posts == 1, 'the all-clear is not repeated')
playerCoords['7'] = { x = 5, y = 0, z = 0 }
HumalikePoseThreatSweep()
playerCoords['7'] = { x = 31, y = 0, z = 0 }
HumalikePoseThreatSweep()
now = now + 11000
HumalikePoseThreatSweep()
assert(#posts == 2, 'coming back and leaving again earns a second all-clear')
posts = {}
playerCoords['7'] = { x = 0, y = 0, z = 0 }
RecordNpcPose('static-1', 'stand_up')
RecordNpcPose('static-1', 'start_dancing', staticTarget)
playerCoords['7'] = { x = 31, y = 0, z = 0 }
now = now + 300000
HumalikePoseThreatSweep()
assert(#posts == 0, 'a dancing NPC is left to enjoy itself')
RecordNpcPose('static-1', 'stand_up')
RecordNpcPose('static-1', 'kneel', staticTarget)
liveEntities[101] = nil
HumalikePoseThreatSweep()
now = now + 300000
HumalikePoseThreatSweep()
assert(#posts == 0, 'no body, no all-clear')

print('pose_threat: ok')
