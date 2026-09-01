
local threads, bagWrites, released, cleared = {}, {}, {}, {}
local now = 10000
local playerCoords = { ['7'] = { x = 0, y = 0, z = 0 } }
local entityCoords = { [101] = { x = 0, y = 0, z = 0 } }
local liveEntities = { [101] = true, [700] = true }

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
    return at(entityCoords[entity] or { x = 0, y = 0, z = 0 })
end
function Entity(entity)
    return { state = { set = function(_, key, value)
        bagWrites[#bagWrites + 1] = { entity = entity, key = key, value = value }
    end } }
end
function HumalikeDebug() end
function HumalikeReleasePose(target)
    released[#released + 1] = target
    return true
end

Config = { PoseAbandonMs = 120000, PoseAbandonRadius = 60.0, PoseAbandonTickMs = 5000 }
NpcRegistry = { ['static-1'] = { npc_id = 'static-1', entity_id = 101 } }
function ValidateAmbientActionTarget(target)
    if not liveEntities[target.entity_id] then return nil, nil, 'ambient_entity_unavailable' end
    return { npc_id = target.npc_id }, target.entity_id
end

dofile('server/pose_ledger.lua')

local staticTarget = { kind = 'static', npc_id = 'static-1' }
RecordNpcPose('static-1', 'kneel', staticTarget)
assert(NpcPoses['static-1'] == 'kneel')
HumalikePoseAbandonSweep()
now = now + 600000
HumalikePoseAbandonSweep()
assert(NpcPoses['static-1'] == 'kneel', 'a watched NPC keeps its pose indefinitely')
playerCoords['7'] = { x = 500, y = 0, z = 0 }
HumalikePoseAbandonSweep()
assert(NpcPoses['static-1'] == 'kneel', 'the two minutes start now, not retroactively')
now = now + 119000
HumalikePoseAbandonSweep()
assert(NpcPoses['static-1'] == 'kneel', 'still inside the window')
now = now + 2000
HumalikePoseAbandonSweep()
assert(NpcPoses['static-1'] == nil, 'left alone for two minutes: the pose is over')
assert(#released == 1 and released[1] == staticTarget, 'and the body was told to stand up')
assert(#bagWrites == 1 and bagWrites[1].key == 'humalike_action'
    and bagWrites[1].value == nil, 'the deed stops riding the entity')
released, bagWrites = {}, {}
RecordNpcPose('static-1', 'kneel', staticTarget)
playerCoords['7'] = { x = 500, y = 0, z = 0 }
HumalikePoseAbandonSweep()
now = now + 119000
playerCoords['7'] = { x = 0, y = 0, z = 0 }
HumalikePoseAbandonSweep()
playerCoords['7'] = { x = 500, y = 0, z = 0 }
now = now + 2000
HumalikePoseAbandonSweep()
assert(NpcPoses['static-1'] == 'kneel', 'the window restarts when they come back')
local ambientTarget = { kind = 'ambient', npc_id = 'ambient-1', entity_id = 101 }
RecordNpcPose('ambient-1', 'hands_up', ambientTarget)
liveEntities[101] = nil
HumalikePoseAbandonSweep()
assert(NpcPoses['ambient-1'] == 'hands_up', 'the clock still has to run')
now = now + 121000
HumalikePoseAbandonSweep()
assert(NpcPoses['ambient-1'] == nil, 'a body that is gone does not keep a pose forever')
RecordNpcPose('static-1', 'stand_up')
assert(NpcPoses['static-1'] == nil)

for _, action in ipairs({ 'enter_vehicle', 'exit_vehicle' }) do
    RecordNpcPose('static-1', 'hands_up', staticTarget)
    RecordNpcPose('static-1', action, staticTarget)
    assert(NpcPoses['static-1'] == nil, action .. ' clears the persistent pose ledger')
end
assert(#threads == 1)
local ok, err = pcall(threads[1])
assert(not ok and err == 'stop thread')
local ambientTarget2 = { kind = 'ambient', npc_id = 'ambient-2', entity_id = 101 }
RecordNpcPose('ambient-2', 'kneel', { kind = 'ambient', npc_id = 'ambient-2', entity_id = 555 })
liveEntities[555] = nil          -- the original body is gone
liveEntities[101] = true         -- a fresh ped now carries the NPC
playerCoords['7'] = { x = 0, y = 0, z = 0 }  -- a player is right there
now = now + 1000
HumalikePoseAbandonSweep()        -- old target: poseBody nil -> clock would start
RefreshNpcPoseTarget('ambient-2', ambientTarget2)  -- replay lands on the new body
now = now + 121000
HumalikePoseAbandonSweep()
assert(NpcPoses['ambient-2'] == 'kneel', 'a watched re-embodied pose is kept')

print('pose_abandon: ok')
