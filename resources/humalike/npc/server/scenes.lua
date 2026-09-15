HumalikeNpcScenes = HumalikeNpcScenes or {}
local scenes = {}

local ARCHETYPES = { corner = true, sidewalk = true, walk = true, run = true, car = true,
    bikes = true, ride = true }
local VEHICLE_ARCHETYPES = { car = true, bikes = true, ride = true }
local MAX_SLOTS = 8
local MAX_CANDIDATES = 6

local function cfg()
    return Config.Scenes
end

local function validVehicle(vehicle)
    return type(vehicle) == 'table' and HumalikeValidId(vehicle.vehicle_id)
        and HumalikeValidId(vehicle.model) and type(vehicle.model_hash) == 'number'
        and vehicle.model_hash == HumalikeUnsignedHash(GetHashKey(vehicle.model))
        and (vehicle.spawn_type == 'automobile' or vehicle.spawn_type == 'bike')
end

local function validSceneShape(scene)
    return type(scene) == 'table' and HumalikeValidId(scene.scene_id)
        and (scene.group_id == nil or type(scene.group_id) == 'string')
        and type(scene.routing_bucket) == 'number' and scene.routing_bucket % 1 == 0
        and scene.routing_bucket >= 0
        and (scene.zone_code == nil or type(scene.zone_code) == 'string')
        and (scene.anchor_session_id == nil or type(scene.anchor_session_id) == 'number')
        and type(scene.candidates) == 'table' and #scene.candidates >= 1
        and #scene.candidates <= MAX_CANDIDATES
        and (scene.vehicles == nil or type(scene.vehicles) == 'table')
        and type(scene.body_ids) == 'table' and #scene.body_ids >= 1
        and #scene.body_ids <= MAX_SLOTS
end

-- A valid scene names bodies the plan wants, each once, seated in its own
-- vehicles when the archetype rides; a body's slot is its position here
-- (0 leads). nil rejects the whole crew.
local function validScene(scene, wanted)
    if not validSceneShape(scene) then return nil end
    for _, point in ipairs(scene.candidates) do
        if not HumalikeNpcPopulation.ValidPoint(point) then return nil end
    end
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
            or body.routing_bucket ~= scene.routing_bucket
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
-- resource will spawn by scene id; a rejected or duplicated id maps to false,
-- an archetype this build does not know to 'unknown' (its bodies are left to
-- the edge's pending TTL, not reported failed).
function HumalikeNpcScenes.Accept(rawScenes, wanted, allowed)
    local accepted = {}
    if not allowed or type(rawScenes) ~= 'table' then return accepted end
    for _, raw in ipairs(rawScenes) do
        local sceneId = type(raw) == 'table' and HumalikeValidId(raw.scene_id) and raw.scene_id or nil
        local entry = sceneId and ARCHETYPES[raw.archetype] and validScene(raw, wanted) or nil
        if not sceneId then
            HumalikeDebug('population scene rejected: %s', tostring(sceneId))
        elseif accepted[sceneId] ~= nil then
            HumalikeDebug('population scene %s listed twice', sceneId)
            accepted[sceneId] = false
        elseif not ARCHETYPES[raw.archetype] then
            HumalikeDebug('population scene %s: unknown archetype %s', sceneId, tostring(raw.archetype))
            accepted[sceneId] = 'unknown'
        elseif not entry then
            HumalikeDebug('population scene rejected: %s', sceneId)
            accepted[sceneId] = false
        else
            accepted[sceneId] = entry
        end
    end
    return accepted
end

local function ownsVehicle(crew, vehicle)
    return DoesEntityExist(vehicle.handle)
        and Entity(vehicle.handle).state.humalike_scene_id == crew.id
end

-- True once none of the crew's vehicles is left; a player inside keeps one
-- for the next tick unless `force`.
local function deleteVehicles(crew, force)
    local remaining = {}
    for _, vehicle in ipairs(crew.vehicles) do
        if ownsVehicle(crew, vehicle) then
            if force or not HumalikePlayerInVehicle(vehicle.handle) then
                DeleteEntity(vehicle.handle)
            else
                remaining[#remaining + 1] = vehicle
            end
        end
    end
    crew.vehicles = remaining
    return #remaining == 0
end

-- A spawn failure anywhere fails the crew: every body spawn_failed, vehicles gone.
local function fail(crew)
    if crew.failing then return end
    crew.failing = true
    deleteVehicles(crew, true)
    for _, record in ipairs(crew.records) do HumalikeNpcPopulation.Fail(record) end
    if scenes[crew.id] == crew then scenes[crew.id] = nil end
end

-- A legitimate release is not a failure: the crew leaves with `cause` and no
-- body is reported failed.
local function release(crew, cause)
    deleteVehicles(crew, true)
    for _, record in ipairs(crew.records) do
        HumalikeNpcPopulation.Retire(record, record.release_requested or cause)
    end
    if scenes[crew.id] == crew then scenes[crew.id] = nil end
end

local function referenced(crew, vehicleId)
    for _, record in ipairs(crew.records) do
        if record.vehicle_id == vehicleId then return true end
    end
    return false
end

local function pruneVehicles(crew)
    local kept = {}
    for _, vehicle in ipairs(crew.vehicles) do
        if referenced(crew, vehicle.id) then
            kept[#kept + 1] = vehicle
        elseif ownsVehicle(crew, vehicle) then
            DeleteEntity(vehicle.handle)
        end
    end
    crew.vehicles = kept
end

local function hasDriver(records)
    for _, record in ipairs(records) do
        if record.seat == -1 then return true end
    end
    return false
end

-- Bodies the edge let go while the crew was still building are dropped from
-- the build; it goes on while a body (and, in a car, the driver) remains.
-- Returns true when the build must stop: the crew was failed or released.
local function dropReleased(crew)
    if scenes[crew.id] ~= crew then return true end
    local remaining = {}
    for _, record in ipairs(crew.records) do
        if HumalikeNpcPopulation.Holds(record) and record.status == 'spawning' then
            if record.release_requested then
                HumalikeNpcPopulation.Retire(record, record.release_requested)
            else
                remaining[#remaining + 1] = record
            end
        elseif not record.release_requested then
            fail(crew) -- gone without a release: a timed-out spawn
            return true
        end
    end
    crew.records = remaining
    pruneVehicles(crew)
    if #remaining == 0 or (crew.archetype == 'car' and not hasDriver(remaining)) then
        release(crew, 'despawned')
        return true
    end
    return false
end

local function bikeSide(index)
    if index == 0 then return 0.0 end
    return cfg().BikeSpacing * math.ceil(index / 2) * (index % 2 == 1 and 1 or -1)
end

local function footOffset(archetype, slot, count)
    local tunables = cfg()
    if archetype == 'corner' then
        local angle = 2 * math.pi * slot / count
        local radius = tunables.CornerRadius + tunables.CornerRadiusStep * (slot % 3)
        return radius * math.cos(angle), radius * math.sin(angle)
    elseif archetype == 'sidewalk' then
        return 0.0, (slot - (count - 1) / 2) * tunables.SidewalkSpacing
    elseif archetype == 'walk' or archetype == 'run' then
        return 0.0, -tunables.ColumnSpacing * slot
    end
    return 0.0, 0.0
end

local function createVehicle(crew, vehicle, point, index)
    local side = bikeSide(index)
    local x, y = HumalikeNpcPopulation.OffsetPoint(point, side, 0.0)
    local handle = CreateVehicleServerSetter(GetHashKey(vehicle.model), vehicle.spawn_type,
        x, y, point.z, point.heading or 0.0)
    if not handle or handle <= 0 then return nil end
    SetEntityRoutingBucket(handle, crew.routing_bucket)
    SetEntityOrphanMode(handle, 2)
    local state = Entity(handle).state
    state:set('humalike_npc_kind', 'population_vehicle', true)
    state:set('humalike_scene_id', crew.id, true)
    state:set('humalike_scene_held', false, true)
    local created = { id = vehicle.vehicle_id, handle = handle, side = side }
    crew.vehicles[#crew.vehicles + 1] = created
    local networkId = HumalikeNpcPopulation.AwaitNetworkId(handle)
    if networkId <= 0 then return nil end
    created.network_id = networkId
    return created
end

local function gone(record)
    return not HumalikeNpcPopulation.Holds(record) or record.status == 'released'
end

local function stampRole(crew, record, slot, count)
    local ped = HumalikeNpcPopulation.PedOf(record)
    if not ped then return end
    local state = Entity(ped).state
    local bag = state.humalike_scene
    if type(bag) ~= 'table' then return end
    local ox, oy = footOffset(crew.archetype, slot, count)
    if record.vehicle_id then ox, oy = bag.ox, bag.oy end -- seated bodies keep their vehicle's spot
    if bag.slot == slot and bag.leader_net == crew.leader_net and bag.ox == ox and bag.oy == oy then
        return
    end
    bag.slot, bag.ox, bag.oy, bag.leader_net = slot, ox, oy, crew.leader_net
    state:set('humalike_scene', bag, true)
end

-- A re-pushed plan re-slots the crew by position in body_ids: the first body
-- leads and the formation follows. Nothing is re-spawned or moved; the owning
-- client picks the new role up from the state bag.
local function reslot(crew, entry)
    local byId = {}
    for _, record in ipairs(crew.records) do byId[record.body_id] = record end
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
    for _, record in ipairs(crew.records) do
        if not kept[record] then ordered[#ordered + 1] = record end
    end
    crew.records = ordered
    crew.leader_net = ordered[1].network_id
    for index, record in ipairs(ordered) do
        if kept[record] then stampRole(crew, record, index - 1, #entry.bodies) end
    end
end

local function build(crew, scene, entry)
    local point = HumalikeNpcPopulation.ResolveSpawnPoint({
        scene_id = crew.id,
        candidates = scene.candidates,
        anchor_session_id = scene.anchor_session_id,
        routing_bucket = scene.routing_bucket,
        mode = VEHICLE_ARCHETYPES[crew.archetype] and 'vehicle' or 'foot',
    })
    if dropReleased(crew) then return end
    if not point then
        HumalikeDebug('population scene %s has no ground near any candidate', crew.id)
        fail(crew)
        return
    end
    local byId = {}
    for index, vehicle in ipairs(entry.vehicles) do
        if referenced(crew, vehicle.vehicle_id) then
            local created = createVehicle(crew, vehicle, point, index - 1)
            if not created then
                fail(crew)
                return
            end
            if dropReleased(crew) then return end
            byId[created.id] = created
        end
    end
    -- Bodies are placed in their current order; a body dropped meanwhile
    -- shifts nobody who already stands, the final re-slot settles the roles.
    while true do
        local slot, record = nil, nil
        for index, candidate in ipairs(crew.records) do
            if not candidate.ped then
                slot, record = index - 1, candidate
                break
            end
        end
        if not record then break end
        local vehicle = record.vehicle_id and byId[record.vehicle_id] or nil
        local ox, oy = footOffset(crew.archetype, slot, #crew.records)
        if vehicle then ox, oy = vehicle.side, 0.0 end
        local placement = {
            ox = ox,
            oy = oy,
            vehicle = vehicle and vehicle.handle or nil,
            seat = record.seat,
            scene = {
                id = crew.id,
                archetype = crew.archetype,
                slot = slot,
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
            fail(crew)
            return
        end
        if dropReleased(crew) then return end
    end
    crew.leader_net = crew.records[1].network_id
    reslot(crew, crew.pending or entry)
    crew.pending = nil
    for _, record in ipairs(crew.records) do
        HumalikeNpcPopulation.Activate(record)
        if scenes[crew.id] ~= crew then return end -- a refused bind took the crew down
    end
    crew.status = 'live'
end

local function spawnScene(sceneId, entry, released)
    local fresh = scenes[sceneId] == nil
    for _, body in ipairs(entry.bodies) do
        if HumalikeNpcPopulation.Tracked(body.body_id) or released[body.body_id] then
            fresh = false
        end
    end
    if not fresh then
        local crew = scenes[sceneId]
        if crew and crew.status == 'live' then
            reslot(crew, entry)
        elseif crew then
            crew.pending = entry
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
    local crew = {
        id = sceneId,
        archetype = scene.archetype,
        routing_bucket = scene.routing_bucket,
        records = {},
        vehicles = {},
        held = false,
        status = 'spawning',
        started_at = GetGameTimer(),
    }
    for slot, body in ipairs(entry.bodies) do
        crew.records[slot] = HumalikeNpcPopulation.Track(body)
    end
    scenes[sceneId] = crew
    CreateThread(function() build(crew, scene, entry) end)
end

function HumalikeNpcScenes.Spawn(accepted, released)
    for sceneId, entry in pairs(accepted) do
        if type(entry) == 'table' then spawnScene(sceneId, entry, released) end
    end
end

local function heldNow(crew)
    if not HumalikeAmbientControlHeld then return false end
    for _, record in ipairs(crew.records) do
        if not gone(record) and record.network_id
            and HumalikeAmbientControlHeld(record.network_id) then return true end
    end
    return false
end

local function setHeld(crew, held)
    crew.held = held
    for _, record in ipairs(crew.records) do
        local ped = HumalikeNpcPopulation.PedOf(record)
        if ped then Entity(ped).state:set('humalike_scene_held', held, true) end
    end
    for _, vehicle in ipairs(crew.vehicles) do
        if ownsVehicle(crew, vehicle) then
            Entity(vehicle.handle).state:set('humalike_scene_held', held, true)
        end
    end
end

-- A body of a crew that failed to spawn or bind takes the rest with it.
function HumalikeNpcScenes.BodyFailed(record)
    local crew = record.scene_id and scenes[record.scene_id] or nil
    if crew then fail(crew) end
end

local function anyAlive(crew)
    for _, record in ipairs(crew.records) do
        if not gone(record) then return true end
    end
    return false
end

-- A hold on one member stops the crew; the vehicles go once the last body is
-- gone (a stolen vehicle that vanished leaves the bodies to the edge's cull).
-- A build whose bodies all left, or that outlived the spawn timeout, is torn
-- down here so a dead build thread cannot leak its vehicles.
function HumalikeNpcScenes.Reconcile()
    local now = GetGameTimer()
    for sceneId, crew in pairs(scenes) do
        if crew.status == 'spawning' then
            if not anyAlive(crew) then
                deleteVehicles(crew, true)
                scenes[sceneId] = nil
            elseif now - crew.started_at > Config.Population.SpawnTimeoutMs + cfg().BuildMarginMs then
                fail(crew)
            end
        elseif crew.status == 'live' then
            if not anyAlive(crew) then
                if deleteVehicles(crew, false) then scenes[sceneId] = nil end
            else
                local held = heldNow(crew)
                if held ~= crew.held then setHeld(crew, held) end
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
    for sceneId, crew in pairs(scenes) do
        local alive = 0
        for _, record in ipairs(crew.records) do
            if not gone(record) then alive = alive + 1 end
        end
        rows[#rows + 1] = {
            scene_id = sceneId,
            archetype = crew.archetype,
            status = crew.status,
            held = crew.held,
            bodies = alive,
            vehicles = #crew.vehicles,
            leader_net = crew.leader_net,
        }
    end
    table.sort(rows, function(left, right) return left.scene_id < right.scene_id end)
    return rows
end

-- The bodies are already gone by the time the resource stops; only the vehicles are left.
local function deleteAllVehicles()
    for _, crew in pairs(scenes) do deleteVehicles(crew, true) end
    scenes = {}
end

AddEventHandler('humalike:core:stopping', deleteAllVehicles)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    deleteAllVehicles()
end)
