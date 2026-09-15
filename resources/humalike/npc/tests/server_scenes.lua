local convars = {}
function GetConvar(name, default) return convars[name] or default end
dofile('config/shared.lua')

local handlers = {}
local threads = {}
local actions = {}
local clientEvents = {}
local created = {}
local vehicles = {}
local deleted = {}
local entityState = {}
local existing = { [700] = true }
local now = 1000
local nextPed = 100
local nextVehicle = 500
local nextNetworkId = 50
local replyPoint = { x = 20, y = 5, z = 30, heading = 45 }
local reply = true
local heldNetIds = {}
local trace = {}
local failPedAt = nil
local failVehicleAt = nil
local pedCount = 0
local vehicleCount = 0
local warps = {}
local playerSeated = false
local credentials = true
source = 7

function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handlers[name] or {}; handlers[name][#handlers[name] + 1] = handler end
local function fire(name, ...)
    for _, handler in ipairs(handlers[name] or {}) do handler(...) end
end
function CreateThread(callback)
    if #threads < 1 then threads[#threads + 1] = callback else callback() end
end
function Wait(ms) now = now + math.max(ms, 50) end
function GetGameTimer() return now end
function GetPlayers() return { '7' } end
function GetPlayerName(playerId) return playerId == 7 and 'Tester' or nil end
function GetPlayerRoutingBucket() return 2 end
function GetPlayerPed(playerId) return playerId == 7 and 700 or 0 end
function DoesEntityExist(entity) return existing[entity] == true end
function GetEntityCoords(entity)
    if entity == 700 then return { x = 0, y = 0, z = 0 } end
    local row = created[entity] or vehicles[entity]
    return row and { x = row.x, y = row.y, z = row.z } or { x = 0, y = 0, z = 0 }
end
function GetEntityHeading(entity) return created[entity] and created[entity].heading or 0 end
function GetHashKey(model)
    if model == 'a_m_m_business_01' then return -123 end
    if model == 'schafter2' then return -777 end
    if model == 'hexer' then return 888 end
    return 456
end
function CreatePed(_, hash, x, y, z, heading)
    pedCount = pedCount + 1
    if failPedAt and pedCount >= failPedAt then return 0 end
    nextPed = nextPed + 1
    created[nextPed] = { hash = hash, x = x, y = y, z = z, heading = heading }
    existing[nextPed] = true
    trace[#trace + 1] = { 'ped', nextPed }
    return nextPed
end
function CreateVehicleServerSetter(hash, spawnType, x, y, z, heading)
    vehicleCount = vehicleCount + 1
    if failVehicleAt and vehicleCount >= failVehicleAt then return 0 end
    nextVehicle = nextVehicle + 1
    vehicles[nextVehicle] = { hash = hash, spawn_type = spawnType, x = x, y = y, z = z, heading = heading }
    existing[nextVehicle] = true
    trace[#trace + 1] = { 'vehicle', nextVehicle }
    return nextVehicle
end
function TaskWarpPedIntoVehicle(ped, vehicle, seat) warps[#warps + 1] = { ped, vehicle, seat } end
function GetPedInVehicleSeat(_, seat) return (playerSeated and seat == 0) and 700 or 0 end
function IsPedAPlayer(ped) return ped == 700 end
function DeleteEntity(entity)
    deleted[#deleted + 1] = entity
    existing[entity] = nil
end
function SetEntityRoutingBucket(entity, bucket) (created[entity] or vehicles[entity]).bucket = bucket end
function SetEntityOrphanMode(entity, mode) (created[entity] or vehicles[entity]).orphan = mode end
function NetworkGetNetworkIdFromEntity(entity)
    local row = created[entity] or vehicles[entity]
    if not row then return 0 end
    if not row.network_id then
        nextNetworkId = nextNetworkId + 1
        row.network_id = nextNetworkId
    end
    return row.network_id
end
function GetEntityModel(entity) return created[entity].hash end
function GetCurrentResourceName() return 'humalike' end
function HumalikeDebug() end
function Entity(entity)
    entityState[entity] = entityState[entity] or {}
    return { state = setmetatable({
        set = function(_, key, value)
            trace[#trace + 1] = { 'set:' .. key, entity, value }
            entityState[entity][key] = value
        end,
    }, { __index = entityState[entity] }) }
end
function TriggerClientEvent(name, playerId, requestId, candidates, mode)
    clientEvents[#clientEvents + 1] = { name = name, player_id = playerId,
        arg = requestId, candidates = candidates, mode = mode }
    if name == 'humalike:npc:populationSpawnPoint' and reply then
        source = 7
        fire('humalike:npc:populationSpawnPointResult', requestId, replyPoint)
    end
end
function HumalikeAmbientControlHeld(networkId) return heldNetIds[networkId] == true end
function HumalikeWoundedStateOf() return nil end
function HumalikeFindAmbientLease() return nil end
function TriggerEvent() end
function SyncNpcRoster() end
function GetSupportedActions() return { 'wave' } end
function RegisterCommand() end
function print() end
HumaLike = { RuntimeCredentials = function() return credentials end }

HumalikeHttp = {
    PostAction = function(name, payload, callback)
        actions[#actions + 1] = { name = name, payload = payload }
        if not callback then return end
        if name == 'bind_npc_body' then
            callback(true, 200, { status = 'bound' })
        elseif name == 'release_npc_body' then
            callback(true, 200, { released = true })
        elseif name == 'report_npc_bodies' then
            callback(true, 200, { ok = true })
        elseif name == 'report_capabilities' then
            callback(true, 200)
        end
    end,
}

dofile('server/features.lua')
dofile('server/population.lua')
dofile('server/scenes.lua')
dofile('server/main.lua')

local function actionsNamed(name)
    local rows = {}
    for _, action in ipairs(actions) do
        if action.name == name then rows[#rows + 1] = action end
    end
    return rows
end
local function lastAction(name)
    local rows = actionsNamed(name)
    return rows[#rows]
end
local function bodyIds()
    local ids = {}
    for _, row in ipairs(HumalikeNpcPopulation.Bodies()) do ids[row.body_id] = row end
    return ids
end
local function failedIn(report)
    local failed = {}
    for _, bodyId in ipairs(report.payload.failed) do failed[bodyId] = true end
    return failed
end
local function spawnRequests()
    local rows = {}
    for _, event in ipairs(clientEvents) do
        if event.name == 'humalike:npc:populationSpawnPoint' then rows[#rows + 1] = event end
    end
    return rows
end
local function setsOf(key, entity)
    local count = 0
    for _, row in ipairs(trace) do
        if row[1] == 'set:' .. key and (entity == nil or row[2] == entity) then count = count + 1 end
    end
    return count
end
local function near(a, b) return math.abs(a - b) < 0.01 end

-- The capability report carries the feature while the convar is on (default).
fire('humalike:core:ready', { generation = 1 })
local capability = lastAction('report_capabilities')
assert(capability and capability.payload.supported_actions[1] == 'wave')
assert(#capability.payload.features == 1 and capability.payload.features[1] == 'group_scenes',
    'group_scenes is reported while humalike_group_spawns is on')
local capabilityCount = #actionsNamed('report_capabilities')
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_capabilities') == capabilityCount, 'an unchanged convar is not re-posted')
convars.humalike_group_spawns = 'false'
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_capabilities') == capabilityCount + 1, 'a flip re-posts the capabilities')
assert(#lastAction('report_capabilities').payload.features == 0)
assert(HumalikeNpcPopulation.GroupSpawns() == false)
convars.humalike_group_spawns = nil
credentials = false
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_capabilities') == capabilityCount + 1, 'no re-post without credentials')
credentials = true
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_capabilities') == capabilityCount + 2)
assert(lastAction('report_capabilities').payload.features[1] == 'group_scenes')
assert(HumalikeNpcPopulation.GroupSpawns() == true)

local npcId = '12345678-1234-1234-1234-123456789abc'
local function body(bodyId, fields)
    local planned = {
        body_id = bodyId,
        npc_id = npcId,
        model = 'a_m_m_business_01',
        model_hash = 4294967173,
        routing_bucket = 2,
        zone_code = 'DOWNT',
        candidates = { { x = 10, y = 0, z = 30, heading = 90 } },
        anchor_session_id = 7,
    }
    for key, value in pairs(fields or {}) do planned[key] = value end
    if planned.kind == 'extra' then planned.npc_id = nil end
    return planned
end
local function scene(sceneId, archetype, bodyIdList, fields)
    local planned = {
        scene_id = sceneId,
        group_id = 'group-1',
        archetype = archetype,
        routing_bucket = 2,
        zone_code = 'DOWNT',
        candidates = { { x = 10, y = 0, z = 30, heading = 90 } },
        anchor_session_id = 7,
        vehicles = {},
        body_ids = bodyIdList,
    }
    for key, value in pairs(fields or {}) do planned[key] = value end
    return planned
end
local function crew(sceneId, ids, seats)
    local rows = {}
    for slot, bodyId in ipairs(ids) do
        local fields = { scene_id = sceneId, scene_slot = slot - 1 }
        if seats then fields.vehicle_id, fields.seat = seats[slot][1], seats[slot][2] end
        if slot == #ids and not seats then fields.kind = 'extra'; fields.style_seed = 9 end
        rows[#rows + 1] = body(bodyId, fields)
    end
    return rows
end
local revision = 0
local function plan(wanted, scenes, released)
    revision = revision + 1
    assert(HumalikeNpcPopulation.ApplyPlan({ revision = revision, enabled = true,
        wanted = wanted, scenes = scenes, released = released or {} }))
end

-- An invalid scene: every body fails, nothing is asked of a client, no ped.
local requestsBefore, pedsBefore = #spawnRequests(), pedCount
plan(crew('s-bad', { 'b1', 'b2', 'b3' }), { scene('s-bad', 'parade', { 'b1', 'b2', 'b3' }) })
assert(#spawnRequests() == requestsBefore and pedCount == pedsBefore)
local failed = failedIn(lastAction('report_npc_bodies'))
assert(failed.b1 and failed.b2 and failed.b3, 'an unknown archetype fails every body')
assert(next(bodyIds()) == nil)
local function rejected(label, wanted, scenes)
    local requests, peds = #spawnRequests(), pedCount
    plan(wanted, scenes)
    assert(#spawnRequests() == requests and pedCount == peds, label .. ': nothing spawns')
    for _, planned in ipairs(wanted) do
        assert(failedIn(lastAction('report_npc_bodies'))[planned.body_id], label .. ': ' .. planned.body_id .. ' fails')
    end
    assert(next(bodyIds()) == nil, label)
end
rejected('slot mismatch', crew('s-slot', { 'b1', 'b2', 'b3' }),
    { scene('s-slot', 'corner', { 'b2', 'b1', 'b3' }) })
rejected('too small', crew('s-small', { 'b1', 'b2' }), { scene('s-small', 'corner', { 'b1', 'b2' }) })
rejected('foot scene with a vehicle', crew('s-veh', { 'b1', 'b2', 'b3' }),
    { scene('s-veh', 'corner', { 'b1', 'b2', 'b3' }, { vehicles = {
        { vehicle_id = 'v1', model = 'schafter2', model_hash = 4294966519, spawn_type = 'automobile' } } }) })
rejected('car without vehicles', crew('s-car0', { 'b1', 'b2' }, { { 'v1', -1 }, { 'v1', 0 } }),
    { scene('s-car0', 'car', { 'b1', 'b2' }) })
rejected('wrong vehicle hash', crew('s-hash', { 'b1', 'b2' }, { { 'v1', -1 }, { 'v1', 0 } }),
    { scene('s-hash', 'car', { 'b1', 'b2' }, { vehicles = {
        { vehicle_id = 'v1', model = 'schafter2', model_hash = 1, spawn_type = 'automobile' } } }) })
rejected('seat in a vehicle the scene lacks', crew('s-seat', { 'b1', 'b2' }, { { 'v9', -1 }, { 'v1', 0 } }),
    { scene('s-seat', 'car', { 'b1', 'b2' }, { vehicles = {
        { vehicle_id = 'v1', model = 'schafter2', model_hash = 4294966519, spawn_type = 'automobile' } } }) })
rejected('scene body without its scene', crew('s-missing', { 'b1', 'b2', 'b3' }), {})
local lone = body('lone', { scene_slot = 0 })
rejected('a lone body carrying a slot', { lone }, {})
rejected('candidates out of range', crew('s-far', { 'b1', 'b2', 'b3' }),
    { scene('s-far', 'corner', { 'b1', 'b2', 'b3' }, { candidates = { { x = 99999, y = 0, z = 0 } } }) })

-- A foot scene: one spawn point, three peds on a ring, one state bag each.
requestsBefore = #spawnRequests()
plan(crew('s-corner', { 'c1', 'c2', 'c3' }), { scene('s-corner', 'corner', { 'c1', 'c2', 'c3' }) })
assert(#spawnRequests() == requestsBefore + 1, 'one point is resolved for the crew')
local request = spawnRequests()[#spawnRequests()]
assert(request.mode == 'foot' and request.arg:match('^s%-corner:'))
local rows = bodyIds()
assert(rows.c1.status == 'bound' and rows.c2.status == 'bound' and rows.c3.status == 'extra')
assert(rows.c1.scene_id == 'c1' or rows.c1.scene_id == 's-corner')
assert(rows.c1.scene_id == 's-corner' and rows.c3.scene_id == 's-corner', 'Bodies() rows carry the scene')
local peds = { rows.c1.handle, rows.c2.handle, rows.c3.handle }
local positions = {}
for slot, ped in ipairs(peds) do
    local row = created[ped]
    local dx, dy = row.x - 20, row.y - 5
    local radius = math.sqrt(dx * dx + dy * dy)
    assert(radius >= 1.39 and radius <= 1.91, 'ring radius between 1.4 and 1.9 m')
    local key = ('%.2f:%.2f'):format(row.x, row.y)
    assert(not positions[key], 'distinct offsets')
    positions[key] = true
    assert(row.heading == 45 and row.bucket == 2 and row.orphan == 2)
    local bag = entityState[ped].humalike_scene
    assert(type(bag) == 'table' and bag.id == 's-corner' and bag.archetype == 'corner')
    assert(bag.slot == slot - 1 and bag.ax == 20 and bag.ay == 5 and bag.az == 30 and bag.heading == 45)
    assert(near(bag.ox, dx * math.cos(math.rad(45)) + dy * math.sin(math.rad(45))), 'ox is the offset to the right')
    assert(bag.leader_net == created[peds[1]].network_id, 'the leader net id is stamped on every member')
    assert(bag.vehicle_net == nil and bag.seat == nil)
    assert(entityState[ped].humalike_scene_held == false)
    assert(entityState[ped].humalike_npc_kind == 'population')
end
assert(entityState[peds[3]].humalike_body_kind == 'extra' and entityState[peds[3]].humalike_style_seed == 9)
assert(#actionsNamed('bind_npc_body') == 2, 'the two personas are bound, the extra is not')
local report = lastAction('report_npc_bodies')
assert(#report.payload.spawned == 3 and #report.payload.failed == 0)
assert(HumalikeNpcScenes.Count() == 1 and HumalikeNpcScenes.Scenes()[1].status == 'live')
assert(HumalikeNpcScenes.Scenes()[1].bodies == 3)

-- Hold propagation: any held member flags the whole crew, written once per change.
local heldBefore = setsOf('humalike_scene_held')
heldNetIds[created[peds[2]].network_id] = true
HumalikeNpcPopulation.Reconcile()
assert(setsOf('humalike_scene_held') == heldBefore + 3, 'held is written on every member')
for _, ped in ipairs(peds) do assert(entityState[ped].humalike_scene_held == true) end
HumalikeNpcPopulation.Reconcile()
assert(setsOf('humalike_scene_held') == heldBefore + 3, 'only on change')
heldNetIds[created[peds[2]].network_id] = nil
HumalikeNpcPopulation.Reconcile()
assert(setsOf('humalike_scene_held') == heldBefore + 6)
for _, ped in ipairs(peds) do assert(entityState[ped].humalike_scene_held == false) end

-- Re-listing a live scene changes nothing; the plan releases it as a unit.
requestsBefore, pedsBefore = #spawnRequests(), pedCount
plan(crew('s-corner', { 'c1', 'c2', 'c3' }), { scene('s-corner', 'corner', { 'c1', 'c2', 'c3' }) })
assert(#spawnRequests() == requestsBefore and pedCount == pedsBefore and HumalikeNpcScenes.Count() == 1)
plan({}, {}, { 'c1', 'c2', 'c3' })
assert(next(bodyIds()) == nil)
for _, ped in ipairs(peds) do assert(existing[ped] == nil, 'every member is deleted') end
HumalikeNpcPopulation.Reconcile()
assert(HumalikeNpcScenes.Count() == 0, 'a foot scene with no bodies left is dropped')

-- A shrinking walk scene: the leader is released, the next plan re-slots the rest.
plan(crew('s-walk', { 'w1', 'w2', 'w3' }), { scene('s-walk', 'walk', { 'w1', 'w2', 'w3' }) })
rows = bodyIds()
local walkers = { rows.w1.handle, rows.w2.handle, rows.w3.handle }
assert(entityState[walkers[3]].humalike_scene.slot == 2 and near(entityState[walkers[3]].humalike_scene.oy, -2.6))
assert(entityState[walkers[2]].humalike_scene.leader_net == created[walkers[1]].network_id)
local walkPlan = crew('s-walk', { 'w2', 'w3' })
walkPlan[2].kind, walkPlan[2].style_seed, walkPlan[2].npc_id = nil, nil, npcId
pedsBefore = pedCount
local sceneSets = setsOf('humalike_scene')
plan(walkPlan, { scene('s-walk', 'walk', { 'w2', 'w3' }) }, { 'w1' })
assert(pedCount == pedsBefore, 'nothing is re-spawned')
assert(existing[walkers[1]] == nil and bodyIds().w1 == nil, 'the old leader is released')
assert(existing[walkers[2]] and existing[walkers[3]], 'the others stay where they are')
assert(setsOf('humalike_scene') == sceneSets + 2, 'both remaining bags are rewritten')
local promoted = entityState[walkers[2]].humalike_scene
assert(promoted.slot == 0 and promoted.oy == 0.0 and promoted.leader_net == created[walkers[2]].network_id,
    'the next body leads')
local trailing = entityState[walkers[3]].humalike_scene
assert(trailing.slot == 1 and near(trailing.oy, -1.3) and trailing.leader_net == created[walkers[2]].network_id,
    'the last body closes up behind the new leader')
assert(HumalikeNpcScenes.Scenes()[1].leader_net == created[walkers[2]].network_id)
assert(not failedIn(lastAction('report_npc_bodies')).w2 and not failedIn(lastAction('report_npc_bodies')).w3,
    'a re-slot fails nobody')
plan(walkPlan, { scene('s-walk', 'walk', { 'w2', 'w3' }) })
assert(setsOf('humalike_scene') == sceneSets + 2, 'an unchanged crew is not rewritten')
plan({}, {}, { 'w2', 'w3' })
HumalikeNpcPopulation.Reconcile()
assert(HumalikeNpcScenes.Count() == 0)

-- A car scene: the vehicle first, then seated bodies warped in.
local sedan = { vehicle_id = 'v1', model = 'schafter2', model_hash = 4294966519, spawn_type = 'automobile' }
local traceBefore = #trace
plan(crew('s-car', { 'd1', 'p1', 'p2' }, { { 'v1', -1 }, { 'v1', 0 }, { 'v1', 1 } }),
    { scene('s-car', 'car', { 'd1', 'p1', 'p2' }, { vehicles = { sedan } }) })
assert(spawnRequests()[#spawnRequests()].mode == 'vehicle', 'a vehicle scene asks for a road node')
local order = {}
for index = traceBefore + 1, #trace do
    if trace[index][1] == 'vehicle' or trace[index][1] == 'ped' then order[#order + 1] = trace[index] end
end
assert(#order == 4 and order[1][1] == 'vehicle' and order[2][1] == 'ped', 'the vehicle is created before any ped')
local sedanHandle = order[1][2]
assert(vehicles[sedanHandle].hash == -777 and vehicles[sedanHandle].spawn_type == 'automobile')
assert(vehicles[sedanHandle].x == 20 and vehicles[sedanHandle].y == 5 and vehicles[sedanHandle].heading == 45,
    'a car sits on the node')
assert(vehicles[sedanHandle].bucket == 2 and vehicles[sedanHandle].orphan == 2)
assert(entityState[sedanHandle].humalike_npc_kind == 'population_vehicle')
assert(entityState[sedanHandle].humalike_scene_id == 's-car')
rows = bodyIds()
assert(rows.d1.status == 'bound' and rows.p1.status == 'bound' and rows.p2.status == 'bound')
assert(#warps == 3)
assert(warps[1][1] == rows.d1.handle and warps[1][2] == sedanHandle and warps[1][3] == -1)
assert(warps[2][1] == rows.p1.handle and warps[2][3] == 0)
assert(warps[3][1] == rows.p2.handle and warps[3][3] == 1)
local driverBag = entityState[rows.d1.handle].humalike_scene
assert(driverBag.vehicle_net == vehicles[sedanHandle].network_id and driverBag.seat == -1)
assert(entityState[rows.p2.handle].humalike_scene.seat == 1)
assert(driverBag.leader_net == created[rows.d1.handle].network_id)
assert(HumalikeNpcScenes.Scenes()[1].vehicles == 1)

-- Vehicles go once the last body is gone, but never with a player inside.
local carPeds = { rows.d1.handle, rows.p1.handle, rows.p2.handle }
playerSeated = true
plan({}, {}, { 'd1', 'p1', 'p2' })
for _, ped in ipairs(carPeds) do assert(existing[ped] == nil) end
HumalikeNpcPopulation.Reconcile()
assert(existing[sedanHandle] == true, 'a player in a seat keeps the vehicle')
assert(HumalikeNpcScenes.Count() == 1)
playerSeated = false
HumalikeNpcPopulation.Reconcile()
assert(existing[sedanHandle] == nil and deleted[#deleted] == sedanHandle, 'then it is deleted')
assert(HumalikeNpcScenes.Count() == 0)

-- A failed ped tears the whole crew down: vehicle and peds deleted, every body spawn_failed.
failPedAt = pedCount + 3
local releaseCount = #actionsNamed('release_npc_body')
local bindCount = #actionsNamed('bind_npc_body')
plan(crew('s-fail', { 'f1', 'f2', 'f3' }, { { 'v1', -1 }, { 'v1', 0 }, { 'v1', 1 } }),
    { scene('s-fail', 'car', { 'f1', 'f2', 'f3' }, { vehicles = { sedan } }) })
failPedAt = nil
assert(next(bodyIds()) == nil, 'no record survives')
assert(HumalikeNpcScenes.Count() == 0)
local releases = actionsNamed('release_npc_body')
assert(#releases == releaseCount + 3)
local causes = {}
for index = releaseCount + 1, #releases do causes[releases[index].payload.body_id] = releases[index].payload.cause end
assert(causes.f1 == 'spawn_failed' and causes.f2 == 'spawn_failed' and causes.f3 == 'spawn_failed')
failed = failedIn(lastAction('report_npc_bodies'))
assert(failed.f1 and failed.f2 and failed.f3)
local failVehicle = nextVehicle
assert(existing[failVehicle] == nil, 'the vehicle is deleted')
for handle in pairs(created) do assert(existing[handle] == nil, 'no ped is left') end
assert(#actionsNamed('bind_npc_body') == bindCount, 'nothing was bound for the failed crew')

-- A failed vehicle fails the crew before any ped exists.
failVehicleAt = vehicleCount + 1
pedsBefore = pedCount
plan(crew('s-noveh', { 'g1', 'g2' }, { { 'v1', -1 }, { 'v1', 0 } }),
    { scene('s-noveh', 'car', { 'g1', 'g2' }, { vehicles = { sedan } }) })
failVehicleAt = nil
assert(pedCount == pedsBefore and next(bodyIds()) == nil)
failed = failedIn(lastAction('report_npc_bodies'))
assert(failed.g1 and failed.g2)

-- No road node near any candidate fails the crew too.
reply = false
plan(crew('s-nopoint', { 'h1', 'h2' }, { { 'v1', -1 }, { 'v1', 0 } }),
    { scene('s-nopoint', 'car', { 'h1', 'h2' }, { vehicles = { sedan } }) })
reply = true
assert(next(bodyIds()) == nil and pedCount == pedsBefore)
failed = failedIn(lastAction('report_npc_bodies'))
assert(failed.h1 and failed.h2)

-- Bikes line up across the heading; a stop deletes the vehicles.
local bike = function(id)
    return { vehicle_id = id, model = 'hexer', model_hash = 888, spawn_type = 'bike' }
end
plan(crew('s-bikes', { 'k1', 'k2', 'k3' }, { { 'w1', -1 }, { 'w2', -1 }, { 'w3', -1 } }),
    { scene('s-bikes', 'bikes', { 'k1', 'k2', 'k3' }, { vehicles = { bike('w1'), bike('w2'), bike('w3') } }) })
rows = bodyIds()
assert(rows.k1.status == 'bound' and rows.k2.status == 'bound' and rows.k3.status == 'bound')
local bikeHandles = { nextVehicle - 2, nextVehicle - 1, nextVehicle }
local right = { x = math.cos(math.rad(45)), y = math.sin(math.rad(45)) }
assert(vehicles[bikeHandles[1]].x == 20 and vehicles[bikeHandles[1]].y == 5)
assert(near(vehicles[bikeHandles[2]].x, 20 + 2.2 * right.x) and near(vehicles[bikeHandles[2]].y, 5 + 2.2 * right.y),
    'the second bike sits 2.2 m to the right')
assert(near(vehicles[bikeHandles[3]].x, 20 - 2.2 * right.x) and near(vehicles[bikeHandles[3]].y, 5 - 2.2 * right.y),
    'the third 2.2 m to the left')
assert(vehicles[bikeHandles[2]].spawn_type == 'bike')
assert(near(created[rows.k2.handle].x, vehicles[bikeHandles[2]].x), 'a rider is created at its bike')
assert(entityState[rows.k2.handle].humalike_scene.vehicle_net == vehicles[bikeHandles[2]].network_id)
assert(#warps == 8, 'car 3, failed crew 2, bikes 3')
fire('humalike:core:stopping')
for _, handle in ipairs(bikeHandles) do assert(existing[handle] == nil, 'scene vehicles are deleted on stop') end
for _, bodyId in ipairs({ 'k1', 'k2', 'k3' }) do assert(existing[rows[bodyId].handle] == nil) end
fire('onResourceStop', 'humalike')

-- With the convar off, scenes are ignored and their bodies fail; lone bodies still spawn.
convars.humalike_group_spawns = 'false'
requestsBefore, pedsBefore = #spawnRequests(), pedCount
local stateCount = 0
for _, event in ipairs(clientEvents) do
    if event.name == 'humalike:npc:populationState' then stateCount = stateCount + 1 end
end
local wanted = crew('s-off', { 'o1', 'o2', 'o3' })
wanted[#wanted + 1] = body('alone')
plan(wanted, { scene('s-off', 'corner', { 'o1', 'o2', 'o3' }) })
assert(pedCount == pedsBefore + 1 and bodyIds().alone.status == 'bound', 'the lone body spawns')
assert(bodyIds().o1 == nil and bodyIds().o2 == nil and bodyIds().o3 == nil)
failed = failedIn(lastAction('report_npc_bodies'))
assert(failed.o1 and failed.o2 and failed.o3 and not failed.alone)
assert(HumalikeNpcScenes.Count() == 0)
local lastState = clientEvents[#clientEvents]
for index = #clientEvents, 1, -1 do
    if clientEvents[index].name == 'humalike:npc:populationState' then lastState = clientEvents[index] break end
end
assert(lastState.arg.group_spawns == false, 'the state event carries the flag')
convars.humalike_group_spawns = nil
HumalikeNpcPopulation.Reconcile()
for index = #clientEvents, 1, -1 do
    if clientEvents[index].name == 'humalike:npc:populationState' then lastState = clientEvents[index] break end
end
assert(lastState.arg.group_spawns == true, 'the reconcile tick rebroadcasts a flipped flag')

print = io.write
print('server_scenes: ok\n')
