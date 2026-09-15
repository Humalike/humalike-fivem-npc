HumalikeNpcScenes = HumalikeNpcScenes or {}
local scenes = {}

-- (smallest, largest) crew per archetype; fixed on both sides of the wire.
local SIZES = {
    corner = { 3, 6 }, sidewalk = { 3, 6 }, walk = { 2, 4 }, run = { 2, 4 },
    car = { 2, 4 }, bikes = { 2, 5 }, ride = { 1, 1 },
}
local VEHICLE_ARCHETYPES = { car = true, bikes = true, ride = true }
local MAX_SLOTS = 8
local MAX_CANDIDATES = 6
local BIKE_SPACING = 2.2 -- metres between bikes lined up across the heading
local CORNER_RADIUS = 1.4 -- ring around the anchor, up to 1.9 with the slot step
local CORNER_RADIUS_STEP = 0.25
local SIDEWALK_SPACING = 2.4
local COLUMN_SPACING = 1.3 -- walkers and runners behind their leader

local function validId(value)
    return type(value) == 'string' and value ~= '' and #value <= 64
end

local function validVehicle(vehicle)
    return type(vehicle) == 'table' and validId(vehicle.vehicle_id)
        and validId(vehicle.model) and type(vehicle.model_hash) == 'number'
        and vehicle.model_hash == HumalikeUnsignedHash(GetHashKey(vehicle.model))
        and (vehicle.spawn_type == 'automobile' or vehicle.spawn_type == 'bike')
end

local function validSceneShape(scene)
    return type(scene) == 'table' and validId(scene.scene_id)
        and (scene.group_id == nil or type(scene.group_id) == 'string')
        and SIZES[scene.archetype] ~= nil
        and type(scene.routing_bucket) == 'number' and scene.routing_bucket % 1 == 0
        and scene.routing_bucket >= 0
        and (scene.zone_code == nil or type(scene.zone_code) == 'string')
        and (scene.anchor_session_id == nil or type(scene.anchor_session_id) == 'number')
        and type(scene.candidates) == 'table' and #scene.candidates >= 1
        and #scene.candidates <= MAX_CANDIDATES
        and (scene.vehicles == nil or type(scene.vehicles) == 'table')
        and type(scene.body_ids) == 'table'
end

-- A valid scene names bodies the plan wants, in slot order, seated in its own
-- vehicles when the archetype rides; nil rejects the whole crew.
local function validScene(scene, wanted)
    if not validSceneShape(scene) then return nil end
    for _, point in ipairs(scene.candidates) do
        if not HumalikeNpcPopulation.ValidPoint(point) then return nil end
    end
    local size = SIZES[scene.archetype]
    if #scene.body_ids < size[1] or #scene.body_ids > size[2] then return nil end
    local rides = VEHICLE_ARCHETYPES[scene.archetype] == true
    local vehicleList = scene.vehicles or {}
    if #vehicleList > MAX_SLOTS or (#vehicleList > 0) ~= rides then return nil end
    local vehicles = {}
    for _, vehicle in ipairs(vehicleList) do
        if not validVehicle(vehicle) or vehicles[vehicle.vehicle_id] then return nil end
        vehicles[vehicle.vehicle_id] = vehicle
    end
    local bodies, seen, seats = {}, {}, {}
    for index, bodyId in ipairs(scene.body_ids) do
        local body = type(bodyId) == 'string' and wanted[bodyId] or nil
        if not body or seen[bodyId] or body.scene_id ~= scene.scene_id
            or body.scene_slot ~= index - 1 or body.routing_bucket ~= scene.routing_bucket
            or (body.vehicle_id ~= nil) ~= rides then return nil end
        if rides then
            local seat = body.vehicle_id .. ':' .. tostring(body.seat)
            if not vehicles[body.vehicle_id] or seats[seat] then return nil end
            seats[seat] = true
        end
        seen[bodyId] = true
        bodies[index] = body
    end
    return { scene = scene, bodies = bodies, vehicles = vehicleList }
end

-- Validates the plan's scenes against its wanted bodies. Returns the crews the
-- resource will spawn by scene id; a rejected or duplicated id maps to false.
function HumalikeNpcScenes.Accept(rawScenes, wanted, allowed)
    local accepted = {}
    if not allowed or type(rawScenes) ~= 'table' then return accepted end
    for _, raw in ipairs(rawScenes) do
        local entry = validScene(raw, wanted)
        local sceneId = entry and raw.scene_id or nil
        if not sceneId then
            HumalikeDebug('population scene rejected: %s',
                tostring(type(raw) == 'table' and raw.scene_id or nil))
        elseif accepted[sceneId] ~= nil then
            HumalikeDebug('population scene %s listed twice', sceneId)
            accepted[sceneId] = false
        else
            accepted[sceneId] = entry
        end
    end
    return accepted
end

local function ownsVehicle(live, vehicle)
    return DoesEntityExist(vehicle.handle)
        and Entity(vehicle.handle).state.humalike_scene_id == live.id
end

local function playerInside(handle)
    for seat = -1, MAX_SLOTS - 1 do
        local occupant = GetPedInVehicleSeat(handle, seat)
        if occupant and occupant > 0 and IsPedAPlayer(occupant) then return true end
    end
    return false
end

-- True once none of the scene's vehicles is left; a player inside keeps one
-- for the next tick unless `force`.
local function deleteVehicles(live, force)
    local remaining = {}
    for _, vehicle in ipairs(live.vehicles) do
        if ownsVehicle(live, vehicle) then
            if force or not playerInside(vehicle.handle) then
                DeleteEntity(vehicle.handle)
            else
                remaining[#remaining + 1] = vehicle
            end
        end
    end
    live.vehicles = remaining
    return #remaining == 0
end

local function fail(live)
    deleteVehicles(live, true)
    for _, record in ipairs(live.records) do HumalikeNpcPopulation.Abandon(record) end
    if scenes[live.id] == live then scenes[live.id] = nil end
end

-- A release or a timeout that reached one body while the crew was still being
-- built ends the whole build; true when the caller must stop.
local function settle(live)
    local cause, failed = nil, false
    for _, record in ipairs(live.records) do
        if not HumalikeNpcPopulation.Holds(record) or record.status ~= 'spawning' then
            failed = true
        elseif record.release_requested then
            cause = cause or record.release_requested
        end
    end
    if failed then
        fail(live)
        return true
    end
    if cause then
        deleteVehicles(live, true)
        for _, record in ipairs(live.records) do HumalikeNpcPopulation.Retire(record, cause) end
        if scenes[live.id] == live then scenes[live.id] = nil end
        return true
    end
    return false
end

local function bikeSide(index)
    if index == 0 then return 0.0 end
    return BIKE_SPACING * math.ceil(index / 2) * (index % 2 == 1 and 1 or -1)
end

local function footOffset(archetype, slot, count)
    if archetype == 'corner' then
        local angle = 2 * math.pi * slot / count
        local radius = CORNER_RADIUS + CORNER_RADIUS_STEP * (slot % 3)
        return radius * math.cos(angle), radius * math.sin(angle)
    elseif archetype == 'sidewalk' then
        return 0.0, (slot - (count - 1) / 2) * SIDEWALK_SPACING
    elseif archetype == 'walk' or archetype == 'run' then
        return 0.0, -COLUMN_SPACING * slot
    end
    return 0.0, 0.0
end

local function createVehicle(live, vehicle, point, index)
    local side = bikeSide(index)
    local x, y = HumalikeNpcPopulation.OffsetPoint(point, side, 0.0)
    local handle = CreateVehicleServerSetter(GetHashKey(vehicle.model), vehicle.spawn_type,
        x, y, point.z, point.heading or 0.0)
    if not handle or handle <= 0 then return nil end
    SetEntityRoutingBucket(handle, live.routing_bucket)
    SetEntityOrphanMode(handle, 2)
    local state = Entity(handle).state
    state:set('humalike_npc_kind', 'population_vehicle', true)
    state:set('humalike_scene_id', live.id, true)
    state:set('humalike_scene_held', false, true)
    local created = { id = vehicle.vehicle_id, handle = handle, side = side }
    live.vehicles[#live.vehicles + 1] = created
    local networkId = NetworkGetNetworkIdFromEntity(handle)
    local attempts = 0
    while networkId <= 0 and attempts < 50 do
        Wait(0)
        attempts = attempts + 1
        networkId = NetworkGetNetworkIdFromEntity(handle)
    end
    if networkId <= 0 then return nil end
    created.network_id = networkId
    return created
end

local function gone(record)
    return not HumalikeNpcPopulation.Holds(record) or record.status == 'released'
end

local function stampRole(live, record, slot, count)
    local ped = HumalikeNpcPopulation.PedOf(record)
    if not ped then return end
    local state = Entity(ped).state
    local bag = state.humalike_scene
    if type(bag) ~= 'table' then return end
    local ox, oy = footOffset(live.archetype, slot, count)
    if record.vehicle_id then ox, oy = bag.ox, bag.oy end -- seated bodies keep their vehicle's spot
    if bag.slot == slot and bag.leader_net == live.leader_net and bag.ox == ox and bag.oy == oy then
        return
    end
    bag.slot, bag.ox, bag.oy, bag.leader_net = slot, ox, oy, live.leader_net
    state:set('humalike_scene', bag, true)
end

-- The edge re-slots a crew that shrank: the next body leads and the formation
-- follows the new slots. Nothing is re-spawned or moved; the owning client
-- picks the new role up from the state bag.
local function reslot(live, entry)
    local byId = {}
    for _, record in ipairs(live.records) do byId[record.body_id] = record end
    local ordered, kept = {}, {}
    for slot, body in ipairs(entry.bodies) do
        local record = byId[body.body_id]
        if record and not gone(record) then
            record.scene_slot = slot - 1
            ordered[#ordered + 1] = record
            kept[record] = true
        end
    end
    if #ordered == 0 then return end
    for _, record in ipairs(live.records) do
        if not kept[record] then ordered[#ordered + 1] = record end
    end
    live.records = ordered
    live.leader_net = ordered[1].network_id
    for index, record in ipairs(ordered) do
        if kept[record] then stampRole(live, record, index - 1, #entry.bodies) end
    end
end

local function build(live, scene, entry)
    local point = HumalikeNpcPopulation.ResolveSpawnPoint({
        scene_id = live.id,
        candidates = scene.candidates,
        anchor_session_id = scene.anchor_session_id,
        routing_bucket = scene.routing_bucket,
        mode = VEHICLE_ARCHETYPES[live.archetype] and 'vehicle' or 'foot',
    })
    if settle(live) then return end
    if not point then
        HumalikeDebug('population scene %s has no ground near any candidate', live.id)
        fail(live)
        return
    end
    local byId = {}
    for index, vehicle in ipairs(entry.vehicles) do
        local created = createVehicle(live, vehicle, point, index - 1)
        if not created then
            fail(live)
            return
        end
        if settle(live) then return end
        byId[created.id] = created
    end
    local count = #live.records
    for slot, record in ipairs(live.records) do
        local vehicle = record.vehicle_id and byId[record.vehicle_id] or nil
        local ox, oy = footOffset(live.archetype, slot - 1, count)
        if vehicle then ox, oy = vehicle.side, 0.0 end
        local placement = {
            ox = ox,
            oy = oy,
            vehicle = vehicle and vehicle.handle or nil,
            seat = record.seat,
            scene = {
                id = live.id,
                archetype = live.archetype,
                slot = slot - 1,
                ax = point.x,
                ay = point.y,
                az = point.z,
                heading = point.heading or 0.0,
                ox = ox,
                oy = oy,
                vehicle_net = vehicle and vehicle.network_id or nil,
                seat = record.seat,
            },
        }
        if not HumalikeNpcPopulation.Materialise(record, point, placement) then
            fail(live)
            return
        end
        if settle(live) then return end
    end
    live.leader_net = live.records[1].network_id
    reslot(live, live.pending or entry)
    live.pending = nil
    for _, record in ipairs(live.records) do HumalikeNpcPopulation.Activate(record) end
    live.status = 'live'
end

local function spawnScene(sceneId, entry, released)
    local fresh = scenes[sceneId] == nil
    for _, body in ipairs(entry.bodies) do
        if HumalikeNpcPopulation.Tracked(body.body_id) or released[body.body_id] then
            fresh = false
        end
    end
    if not fresh then
        local live = scenes[sceneId]
        if live and live.status == 'live' then
            reslot(live, entry)
        elseif live then
            live.pending = entry
        end
        -- A crew never grows: a body missing from a scene already on the street is lost.
        for _, body in ipairs(entry.bodies) do
            if not HumalikeNpcPopulation.Tracked(body.body_id) and not released[body.body_id] then
                HumalikeNpcPopulation.NoteFailed(body.body_id)
            end
        end
        return
    end
    local scene = entry.scene
    local live = {
        id = sceneId,
        archetype = scene.archetype,
        routing_bucket = scene.routing_bucket,
        records = {},
        vehicles = {},
        held = false,
        status = 'spawning',
    }
    for slot, body in ipairs(entry.bodies) do
        live.records[slot] = HumalikeNpcPopulation.Track(body)
    end
    scenes[sceneId] = live
    CreateThread(function() build(live, scene, entry) end)
end

function HumalikeNpcScenes.Spawn(accepted, released)
    for sceneId, entry in pairs(accepted) do
        if entry then spawnScene(sceneId, entry, released) end
    end
end

local function heldNow(live)
    if not HumalikeAmbientControlHeld then return false end
    for _, record in ipairs(live.records) do
        if not gone(record) and record.network_id
            and HumalikeAmbientControlHeld(record.network_id) then return true end
    end
    return false
end

local function setHeld(live, held)
    live.held = held
    for _, record in ipairs(live.records) do
        local ped = HumalikeNpcPopulation.PedOf(record)
        if ped then Entity(ped).state:set('humalike_scene_held', held, true) end
    end
    for _, vehicle in ipairs(live.vehicles) do
        if ownsVehicle(live, vehicle) then
            Entity(vehicle.handle).state:set('humalike_scene_held', held, true)
        end
    end
end

-- A hold on one member stops the crew; the vehicles go once the last body is
-- gone (a stolen vehicle that vanished leaves the bodies to the edge's cull).
function HumalikeNpcScenes.Reconcile()
    for sceneId, live in pairs(scenes) do
        if live.status == 'live' then
            local alive = false
            for _, record in ipairs(live.records) do
                if not gone(record) then alive = true end
            end
            if not alive then
                if deleteVehicles(live, false) then scenes[sceneId] = nil end
            else
                local held = heldNow(live)
                if held ~= live.held then setHeld(live, held) end
            end
        end
    end
end

function HumalikeNpcScenes.Count()
    local count = 0
    for _ in pairs(scenes) do count = count + 1 end
    return count
end

function HumalikeNpcScenes.Scenes()
    local rows = {}
    for sceneId, live in pairs(scenes) do
        local alive = 0
        for _, record in ipairs(live.records) do
            if not gone(record) then alive = alive + 1 end
        end
        rows[#rows + 1] = {
            scene_id = sceneId,
            archetype = live.archetype,
            status = live.status,
            held = live.held,
            bodies = alive,
            vehicles = #live.vehicles,
            leader_net = live.leader_net,
        }
    end
    table.sort(rows, function(left, right) return left.scene_id < right.scene_id end)
    return rows
end

-- The bodies are already gone by the time the resource stops; only the vehicles are left.
local function deleteAllVehicles()
    for _, live in pairs(scenes) do deleteVehicles(live, true) end
    scenes = {}
end

AddEventHandler('humalike:core:stopping', deleteAllVehicles)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    deleteAllVehicles()
end)
