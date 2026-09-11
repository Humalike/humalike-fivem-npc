local convars = {}
function GetConvar(name, default) return convars[name] or default end
dofile('config/shared.lua')

local handlers = {}
local threads = {}
local deferred = {}
local deferSpawn = false
local loaded = false
local actions = {}
local clientEvents = {}
local created = {}
local deleted = {}
local entityState = {}
local existing = { [700] = true }
local now = 1000
local nextPed = 100
local nextNetworkId = 50
local bindResponse = { status = 'bound' }
local replyPoint = { x = 20, y = 5, z = 30, heading = 45 }
local replySource = 7
local reply = true
local held = false
local wounded = nil
local lease = nil
local resourceStopped = false
local deliverBind = true
local pendingBind
local reportResponse = { ok = true }
local reportOk = true
local holdReport = false
local pendingReport
local releaseOk = true
local noCredentials = false
local trace = {}
source = 7

function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
function CreateThread(callback)
    if not loaded then
        threads[#threads + 1] = callback
    elseif deferSpawn then
        deferred[#deferred + 1] = callback
    else
        callback()
    end
end
function Wait(ms) now = now + math.max(ms, 50) end
function GetGameTimer() return now end
function GetPlayers() return { '7', '8' } end
function GetPlayerName(playerId) return (playerId == 7 or playerId == 8) and 'Tester' or nil end
function GetPlayerRoutingBucket(playerId) return playerId == 8 and 1 or 2 end
function GetPlayerPed(playerId) return playerId == 7 and 700 or 0 end
function DoesEntityExist(entity) return existing[entity] == true end
function GetEntityCoords(entity)
    if entity == 700 then return { x = 0, y = 0, z = 0 } end
    return created[entity] and { x = created[entity].x, y = created[entity].y, z = created[entity].z }
        or { x = 0, y = 0, z = 0 }
end
function GetEntityHeading(entity) return created[entity] and created[entity].heading or 0 end
function GetHashKey(model) return model == 'a_m_m_business_01' and -123 or 456 end
function CreatePed(_, hash, x, y, z, heading)
    nextPed = nextPed + 1
    created[nextPed] = { hash = hash, x = x, y = y, z = z, heading = heading }
    existing[nextPed] = true
    return nextPed
end
function DeleteEntity(entity)
    deleted[#deleted + 1] = entity
    existing[entity] = nil
end
function SetEntityRoutingBucket(entity, bucket) created[entity].bucket = bucket end
function SetEntityOrphanMode(entity, mode) created[entity].orphan = mode end
function NetworkGetNetworkIdFromEntity(entity)
    trace[#trace + 1] = { entity, 'netid' }
    if not created[entity] then return 0 end
    if not created[entity].network_id then
        nextNetworkId = nextNetworkId + 1
        created[entity].network_id = nextNetworkId
    end
    return created[entity].network_id
end
function GetEntityModel(entity) return created[entity].hash end
function GetCurrentResourceName() return 'humalike' end
function HumalikeDebug() end
function Entity(entity)
    entityState[entity] = entityState[entity] or {}
    return { state = setmetatable({
        set = function(_, key, value)
            trace[#trace + 1] = { entity, 'set:' .. key }
            entityState[entity][key] = value
        end,
    }, { __index = entityState[entity] }) }
end
function TriggerClientEvent(name, playerId, requestId, candidates)
    clientEvents[#clientEvents + 1] = { name = name, player_id = playerId,
        arg = requestId, candidates = candidates }
    if name == 'humalike:npc:populationSpawnPoint' and reply then
        source = replySource
        handlers['humalike:npc:populationSpawnPointResult'](requestId, replyPoint)
        source = 7
    end
end
function HumalikeAmbientControlHeld() return held end
function HumalikeWoundedStateOf() return wounded end
function HumalikeFindAmbientLease() return lease end

HumalikeHttp = {
    PostAction = function(name, payload, callback)
        actions[#actions + 1] = { name = name, payload = payload }
        if not callback then return end
        if name == 'bind_npc_body' then
            if deliverBind then callback(true, 200, bindResponse) else pendingBind = callback end
        elseif name == 'release_npc_body' then
            if noCredentials then
                callback(false, 0, nil)
                return
            end
            if resourceStopped then return end
            if releaseOk then callback(true, 200, { released = true }) else callback(false, 401, nil) end
        elseif name == 'report_npc_bodies' then
            if holdReport then
                pendingReport = callback
            elseif reportOk then
                callback(true, 200, reportResponse)
            else
                callback(false, 500, nil)
            end
        end
    end,
}

dofile('server/population.lua')
loaded = true
assert(#threads == 1)

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

handlers['humalike:core:ready']()
local bootReport = lastAction('report_npc_bodies')
assert(bootReport and bootReport.payload.revision == 0, 'the boot report carries revision 0')
assert(#bootReport.payload.spawned == 0 and #bootReport.payload.failed == 0,
    'and tells the edge this runtime holds nothing')
assert(#actions == 1)

local npcId = '12345678-1234-1234-1234-123456789abc'
local function planned(bodyId, anchor)
    return {
        body_id = bodyId,
        npc_id = npcId,
        model = 'a_m_m_business_01',
        model_hash = 4294967173,
        routing_bucket = 2,
        zone_code = 'DOWNT',
        candidates = { { x = 10, y = 0, z = 30, heading = 90 }, { x = 60, y = 0, z = 30, heading = 0 } },
        anchor_session_id = anchor,
    }
end

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 1, enabled = true,
    wanted = { planned('body-1', 7) }, released = {} }))
assert(clientEvents[1].name == 'humalike:npc:populationState')
assert(clientEvents[1].player_id == -1 and clientEvents[1].arg.enabled == true)
assert(HumalikeNpcPopulation.Enabled() == true)
assert(clientEvents[2].name == 'humalike:npc:populationSpawnPoint')
assert(clientEvents[2].player_id == 7)
assert(#clientEvents[2].candidates == 2)
assert(created[101].x == 20 and created[101].y == 5 and created[101].z == 30)
assert(created[101].heading == 45)
assert(created[101].hash == -123)
assert(created[101].bucket == 2 and created[101].orphan == 2)
assert(entityState[101].humalike_npc_kind == 'population')
assert(entityState[101].humalike_body_id == 'body-1')
assert(entityState[101].humalike_body_kind == 'persona')
local function traceIndex(entity, label)
    for index, row in ipairs(trace) do
        if row[1] == entity and row[2] == label then return index end
    end
    return nil
end
assert(traceIndex(101, 'set:humalike_body_kind') < traceIndex(101, 'netid'),
    'the body kind is replicated before the network-id wait can yield')
local bindAction = lastAction('bind_npc_body')
assert(bindAction.payload.body_id == 'body-1')
assert(bindAction.payload.npc_id == npcId)
assert(bindAction.payload.entity_id == 51)
assert(bindAction.payload.model_hash == 4294967173)
assert(bindAction.payload.x == 20 and bindAction.payload.y == 5 and bindAction.payload.z == 30)
assert(bindAction.payload.heading == 45)
assert(bindAction.payload.zone_code == 'DOWNT')
assert(bindAction.payload.routing_bucket == 2)
assert(bodyIds()['body-1'].status == 'bound')
assert(bodyIds()['body-1'].network_id == 51)
assert(#actionsNamed('report_npc_bodies') == 2)
assert(actionsNamed('report_npc_bodies')[2].payload.spawned[1] == 'body-1')
assert(actionsNamed('report_npc_bodies')[2].payload.revision == 1)

local actionCount = #actions
assert(not HumalikeNpcPopulation.ApplyPlan({ revision = 1, enabled = true,
    wanted = { planned('body-1', 7) }, released = {} }))
assert(#actions == actionCount)

lease = { npc_id = npcId, entity_id = 51 }
HumalikeNpcPopulation.Reconcile()
local report = lastAction('report_npc_bodies')
assert(#report.payload.spawned == 1 and report.payload.spawned[1] == 'body-1')
assert(#report.payload.failed == 0)

reply = false
local deletedBefore = #deleted
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 2, enabled = true,
    wanted = { planned('body-1', 7), planned('body-2', 9) }, released = {} }))
assert(clientEvents[#clientEvents].player_id == 7, 'the nearest player in the bucket is asked')
assert(created[102] == nil and #deleted == deletedBefore, 'a silent client means no CreatePed')
local releaseAction = lastAction('release_npc_body')
assert(releaseAction.payload.body_id == 'body-2')
assert(releaseAction.payload.npc_id == npcId)
assert(releaseAction.payload.cause == 'spawn_failed')
assert(bodyIds()['body-2'] == nil)
HumalikeNpcPopulation.Reconcile()
report = lastAction('report_npc_bodies')
assert(#report.payload.failed == 1 and report.payload.failed[1] == 'body-2')
assert(#report.payload.spawned == 1)

reply = true
replyPoint = nil
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 2.2, enabled = true,
    wanted = { planned('body-1', 7), planned('body-2', 9) }, released = {} }))
assert(created[102] == nil and #deleted == deletedBefore, 'no pavement near any candidate: no CreatePed')
assert(lastAction('release_npc_body').payload.body_id == 'body-2')
assert(lastAction('release_npc_body').payload.cause == 'spawn_failed')
assert(lastAction('report_npc_bodies').payload.failed[1] == 'body-2')
replyPoint = { x = 20, y = 5, z = 30, heading = 45 }

bindResponse = { status = 'unavailable', reason = 'server_capacity_reached' }
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 2.5, enabled = true,
    wanted = { planned('body-1', 7), planned('body-2', 9) }, released = {} }))
assert(created[102].x == 20 and created[102].y == 5 and deleted[#deleted] == 102)
assert(lastAction('release_npc_body').payload.body_id == 'body-2')
assert(lastAction('release_npc_body').payload.cause == 'spawn_failed')
assert(bodyIds()['body-2'] == nil)
assert(lastAction('report_npc_bodies').payload.failed[1] == 'body-2')

bindResponse = { status = 'bound' }
replySource = 8
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 3, enabled = true,
    wanted = { planned('body-1', 7), planned('body-3', 7) }, released = {} }))
assert(created[103] == nil, 'a reply from another player is ignored and the spawn fails')
assert(lastAction('release_npc_body').payload.body_id == 'body-3')
assert(lastAction('release_npc_body').payload.cause == 'spawn_failed')
replySource = 7
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 3.5, enabled = true,
    wanted = { planned('body-1', 7), planned('body-3', 7) }, released = {} }))
assert(created[103].x == 20 and created[103].y == 5)
replyPoint = { x = 500, y = 500, z = 30 }
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 4, enabled = true,
    wanted = { planned('body-1', 7), planned('body-3', 7), planned('body-4', 7) }, released = {} }))
assert(created[104] == nil, 'a point far from every candidate fails the spawn')
assert(lastAction('release_npc_body').payload.body_id == 'body-4')
assert(lastAction('release_npc_body').payload.cause == 'spawn_failed')
replyPoint = { x = 20, y = 5, z = 30, heading = 45 }
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 4.5, enabled = true,
    wanted = { planned('body-1', 7), planned('body-3', 7), planned('body-4', 7) }, released = {} }))
assert(created[104].x == 20 and created[104].y == 5)

actionCount = #deleted
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 5, enabled = true,
    wanted = { planned('body-1', 7), planned('body-3', 7) }, released = { 'body-4' } }))
assert(deleted[#deleted] == 104 and #deleted == actionCount + 1)
releaseAction = lastAction('release_npc_body')
assert(releaseAction.payload.body_id == 'body-4' and releaseAction.payload.cause == 'despawned')
assert(bodyIds()['body-4'] == nil)

held = true
actionCount = #deleted
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 6, enabled = true,
    wanted = { planned('body-1', 7) }, released = { 'body-3' } }))
assert(#deleted == actionCount)
assert(bodyIds()['body-3'].status == 'bound' and bodyIds()['body-3'].kept == 'held')
report = lastAction('report_npc_bodies')
assert(#report.payload.spawned == 2)
HumalikeNpcPopulation.Reconcile()
assert(#deleted == actionCount)
held = false
HumalikeNpcPopulation.Reconcile()
assert(deleted[#deleted] == 103)
assert(lastAction('release_npc_body').payload.body_id == 'body-3')
assert(bodyIds()['body-3'] == nil)

wounded = 'wounded'
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 7, enabled = true,
    wanted = {}, released = { 'body-1' } }))
assert(bodyIds()['body-1'].kept == 'wounded')
wounded = nil
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 8, enabled = true,
    wanted = { planned('body-1', 7) }, released = {} }))
assert(bodyIds()['body-1'].kept == nil and bodyIds()['body-1'].status == 'bound')

lease = nil
HumalikeNpcPopulation.Reconcile()
now = now + 31000
actionCount = #deleted
HumalikeNpcPopulation.Reconcile()
assert(deleted[#deleted] == 101 and #deleted == actionCount + 1)
assert(lastAction('release_npc_body').payload.cause == 'despawned')
assert(next(bodyIds()) == nil)

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 9, enabled = true,
    wanted = { planned('body-5', 7) }, released = {} }))
lease = { npc_id = npcId, entity_id = 999 }
HumalikeNpcPopulation.Reconcile()
now = now + 31000
HumalikeNpcPopulation.Reconcile()
assert(lastAction('release_npc_body').payload.body_id == 'body-5')
assert(lastAction('release_npc_body').payload.cause == 'kept_elsewhere')

lease = nil
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 10, enabled = true,
    wanted = { planned('body-6', 7) }, released = {} }))
existing[106] = nil
HumalikeNpcPopulation.Reconcile()
assert(lastAction('release_npc_body').payload.body_id == 'body-6')
assert(lastAction('release_npc_body').payload.cause == 'despawned')
assert(bodyIds()['body-6'] == nil)

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 11, enabled = true,
    wanted = { planned('body-7', 7), { body_id = 'bad', npc_id = npcId } }, released = {} }))
assert(bodyIds()['body-7'].status == 'bound' and bodyIds()['bad'] == nil)
report = lastAction('report_npc_bodies')
assert(#report.payload.failed == 1 and report.payload.failed[1] == 'bad',
    'a body that fails validation is reported failed')
local wrongHash = planned('body-hash', 7)
wrongHash.model_hash = 1
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 11.5, enabled = true,
    wanted = { planned('body-7', 7), wrongHash }, released = {} }))
assert(bodyIds()['body-hash'] == nil, 'a model hash that does not match the model is rejected')
assert(lastAction('report_npc_bodies').payload.failed[1] == 'body-hash')
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 12, enabled = false, wanted = {}, released = {} }))
assert(bodyIds()['body-7'] == nil)
assert(lastAction('release_npc_body').payload.body_id == 'body-7')

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 13, enabled = true,
    wanted = { planned('body-8', 7) }, released = {} }))
resourceStopped = true
actionCount = #deleted
handlers['humalike:core:stopping']()
assert(deleted[#deleted] == 108 and #deleted == actionCount + 1,
    'the entity is deleted before the best-effort release')
assert(lastAction('release_npc_body').payload.body_id == 'body-8')
assert(lastAction('release_npc_body').payload.cause == 'resource_stop')
handlers['onResourceStop']('humalike')
assert(#deleted == actionCount + 1, 'nothing is left for onResourceStop')
assert(bodyIds()['body-8'].status == 'released' and bodyIds()['body-8'].handle == nil,
    'an unanswered stop release keeps only a ped-less record')

resourceStopped = false
local function stateEvents()
    local rows = {}
    for _, event in ipairs(clientEvents) do
        if event.name == 'humalike:npc:populationState' then rows[#rows + 1] = event end
    end
    return rows
end
local function extra(bodyId, seed)
    return {
        body_id = bodyId,
        kind = 'extra',
        model = 'a_m_m_business_01',
        model_hash = 4294967173,
        style_seed = seed,
        routing_bucket = 2,
        zone_code = 'DOWNT',
        candidates = { { x = 10, y = 0, z = 30, heading = 90 } },
        anchor_session_id = 7,
    }
end

local bindCount = #actionsNamed('bind_npc_body')
local stateCount = #stateEvents()
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 14, enabled = true,
    wanted = { extra('extra-1', 777), {
        body_id = 'no-npc', kind = 'persona', model = 'a_m_m_business_01',
        model_hash = 4294967173, routing_bucket = 2,
        candidates = { { x = 10, y = 0, z = 30 } },
    } }, released = {} }))
assert(HumalikeNpcPopulation.Enabled() == true)
assert(#stateEvents() == stateCount, 'staying enabled is not rebroadcast')
assert(created[109] ~= nil and created[109].x == 20)
assert(entityState[109].humalike_npc_kind == 'population')
assert(entityState[109].humalike_body_id == 'extra-1')
assert(entityState[109].humalike_body_kind == 'extra')
assert(entityState[109].humalike_style_seed == 777)
assert(#actionsNamed('bind_npc_body') == bindCount, 'extras are never bound')
assert(bodyIds()['extra-1'].status == 'extra' and bodyIds()['extra-1'].kind == 'extra')
assert(bodyIds()['no-npc'] == nil, 'a persona body needs an npc_id')
report = lastAction('report_npc_bodies')
assert(report.payload.revision == 14 and report.payload.spawned[1] == 'extra-1')

lease = nil
HumalikeNpcPopulation.Reconcile()
now = now + 31000
HumalikeNpcPopulation.Reconcile()
assert(bodyIds()['extra-1'].status == 'extra', 'extras ignore the lease grace')

stateCount = #stateEvents()
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 15, enabled = true,
    wanted = { extra('extra-1', 777) }, released = {} }))
assert(#stateEvents() == stateCount, 'an unchanged state is not rebroadcast')

actionCount = #deleted
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 16, enabled = true,
    wanted = {}, released = { 'extra-1' } }))
assert(deleted[#deleted] == 109 and #deleted == actionCount + 1)
releaseAction = lastAction('release_npc_body')
assert(releaseAction.payload.body_id == 'extra-1' and releaseAction.payload.npc_id == nil)
assert(releaseAction.payload.cause == 'despawned')
assert(bodyIds()['extra-1'] == nil)

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 17, enabled = true,
    wanted = { extra('extra-2', nil) }, released = {} }))
assert(bodyIds()['extra-2'].status == 'extra')
existing[110] = nil
HumalikeNpcPopulation.Reconcile()
assert(lastAction('release_npc_body').payload.body_id == 'extra-2')
assert(bodyIds()['extra-2'] == nil, 'a vanished extra is released')

source = 7
HumalikeNpcPopulation.SendState(7)
local joinEvent = clientEvents[#clientEvents]
assert(joinEvent.name == 'humalike:npc:populationState')
assert(joinEvent.player_id == 7 and joinEvent.arg.enabled == true)

stateCount = #stateEvents()
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 18, enabled = false, wanted = {}, released = {} }))
assert(HumalikeNpcPopulation.Enabled() == false)
assert(#stateEvents() == stateCount + 1 and stateEvents()[#stateEvents()].arg.enabled == false)
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 19, enabled = 'yes',
    wanted = { extra('extra-3', 1) }, released = {} }))
assert(HumalikeNpcPopulation.Enabled() == false and #stateEvents() == stateCount + 1)
assert(bodyIds()['extra-3'] == nil, 'a non-boolean enabled flag spawns nothing')

local function behaved(bodyId, fields)
    local body = planned(bodyId, 7)
    for key, value in pairs(fields) do body[key] = value end
    return body
end
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 20, enabled = true, wanted = {
    behaved('body-9', { behaviour = 'scenario', scenario = 'WORLD_HUMAN_SMOKING', walk_rate = 0.8 }),
    behaved('body-10', {}),
    behaved('body-11', { behaviour = 'stand' }),
    behaved('body-12', { behaviour = 'sleep' }),
    behaved('body-13', { scenario = 'world_human_smoking' }),
    behaved('body-14', { scenario = string.rep('A', 49) }),
    behaved('body-15', { walk_rate = 1.2 }),
    behaved('body-16', { walk_rate = 0.4 }),
    behaved('body-17', { walk_rate = '0.8' }),
}, released = {} }))
local rows = bodyIds()
assert(rows['body-9'] and rows['body-10'] and rows['body-11'], 'valid behaviours spawn')
for _, bodyId in ipairs({ 'body-12', 'body-13', 'body-14', 'body-15', 'body-16', 'body-17' }) do
    assert(rows[bodyId] == nil, bodyId .. ' must be rejected')
end
local state9 = entityState[rows['body-9'].handle]
assert(state9.humalike_body_behaviour == 'scenario')
assert(state9.humalike_body_scenario == 'WORLD_HUMAN_SMOKING')
assert(state9.humalike_walk_rate == 0.8)
local state10 = entityState[rows['body-10'].handle]
assert(state10.humalike_body_behaviour == 'wander' and state10.humalike_body_scenario == nil)
assert(state10.humalike_walk_rate == 1.0, 'walk_rate defaults to 1.0')
local state11 = entityState[rows['body-11'].handle]
assert(state11.humalike_body_behaviour == 'stand' and state11.humalike_body_scenario == nil)

local lastState = stateEvents()[#stateEvents()]
assert(lastState.arg.enabled == true and lastState.arg.cops_allowed == false,
    'the state event carries the server-side cops setting')
convars.humalike_population_cops = 'true'
stateCount = #stateEvents()
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 21, enabled = true,
    wanted = { planned('body-9', 7), planned('body-10', 7), planned('body-11', 7) }, released = {} }))
assert(#stateEvents() == stateCount + 1, 'a changed cops setting is broadcast even with an unchanged state')
assert(stateEvents()[#stateEvents()].arg.enabled == true)
assert(stateEvents()[#stateEvents()].arg.cops_allowed == true)
HumalikeNpcPopulation.SendState(7)
assert(clientEvents[#clientEvents].arg.cops_allowed == true and clientEvents[#clientEvents].player_id == 7)
convars.humalike_population_cops = nil
stateCount = #stateEvents()
HumalikeNpcPopulation.Reconcile()
assert(#stateEvents() == stateCount + 1 and stateEvents()[#stateEvents()].arg.cops_allowed == false,
    'the reconcile tick picks up a convar change without a new plan')
convars.humalike_population_cops = 'true'
HumalikeNpcPopulation.Reconcile()
assert(#stateEvents() == stateCount + 2 and stateEvents()[#stateEvents()].arg.cops_allowed == true)
HumalikeNpcPopulation.Reconcile()
assert(#stateEvents() == stateCount + 2, 'an unchanged convar is not rebroadcast')
convars.humalike_population_cops = nil
HumalikeNpcPopulation.Reconcile()

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 22, enabled = true, wanted = {}, released = {} }))
local remaining = HumalikeNpcPopulation.Bodies()
assert(#remaining == 1 and remaining[1].body_id == 'body-8' and remaining[1].status == 'released'
    and remaining[1].handle == nil,
    'an empty plan leaves only the unanswered ped-less record')
deliverBind = false
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 23, enabled = true,
    wanted = { planned('body-20', 7) }, released = {} }))
assert(bodyIds()['body-20'].status == 'spawning' and type(pendingBind) == 'function')
local slowPed = bodyIds()['body-20'].handle
assert(existing[slowPed])
HumalikeNpcPopulation.Reconcile()
assert(bodyIds()['body-20'].status == 'spawning', 'a young spawn is left alone')
now = now + 31000
actionCount = #deleted
HumalikeNpcPopulation.Reconcile()
assert(deleted[#deleted] == slowPed and #deleted == actionCount + 1, 'a spawn older than SpawnTimeoutMs is torn down')
assert(lastAction('release_npc_body').payload.body_id == 'body-20')
assert(lastAction('release_npc_body').payload.cause == 'spawn_failed')
assert(bodyIds()['body-20'] == nil)
report = lastAction('report_npc_bodies')
assert(report.payload.failed[1] == 'body-20')
existing[slowPed] = true
local lateBind = pendingBind
pendingBind = nil
local reportCount = #actionsNamed('report_npc_bodies')
local releaseCountBefore = #actionsNamed('release_npc_body')
lateBind(true, 200, { status = 'bound' })
assert(deleted[#deleted] == slowPed and #deleted == actionCount + 2,
    'a late bind for a released record only deletes a lingering ped')
assert(bodyIds()['body-20'] == nil, 'the record is not resurrected')
assert(#actionsNamed('report_npc_bodies') == reportCount, 'a late bind sends no report')
assert(#actionsNamed('release_npc_body') == releaseCountBefore, 'and posts no second release')

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 24, enabled = true,
    wanted = { planned('body-21', 7) }, released = {} }))
local pendingPed = bodyIds()['body-21'].handle
assert(bodyIds()['body-21'].status == 'spawning' and type(pendingBind) == 'function')
actionCount = #deleted
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 25, enabled = true,
    wanted = {}, released = { 'body-21' } }))
assert(#deleted == actionCount, 'the plan alone does not touch an in-flight spawn')
HumalikeNpcPopulation.Reconcile()
assert(deleted[#deleted] == pendingPed and #deleted == actionCount + 1,
    'the reconcile tick tears down a released in-flight spawn')
assert(lastAction('release_npc_body').payload.body_id == 'body-21')
assert(lastAction('release_npc_body').payload.cause == 'despawned')
assert(bodyIds()['body-21'] == nil)
lateBind = pendingBind
pendingBind = nil
lateBind(true, 200, { status = 'bound' })
assert(#deleted == actionCount + 1 and bodyIds()['body-21'] == nil, 'a late bind resurrects nothing')
deliverBind = true

held = true
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 26, enabled = true,
    wanted = { planned('body-22', 7), planned('body-23', 7) }, released = {} }))
assert(bodyIds()['body-22'].status == 'bound' and bodyIds()['body-23'].status == 'bound')
local unknownPed = bodyIds()['body-22'].handle
reportResponse = { ok = true, unknown = { 'body-22', 'never-existed' } }
actionCount = #deleted
releaseCount = #actionsNamed('release_npc_body')
HumalikeNpcPopulation.Report()
reportResponse = { ok = true }
assert(#deleted == actionCount and bodyIds()['body-22'].kept == 'held',
    'a body the edge does not know stays while it is held')
HumalikeNpcPopulation.Reconcile()
assert(#deleted == actionCount and bodyIds()['body-22'].status == 'bound')
held = false
HumalikeNpcPopulation.Reconcile()
assert(deleted[#deleted] == unknownPed and #deleted == actionCount + 1,
    'the hold ends and the forgotten body is deleted')
assert(#actionsNamed('release_npc_body') == releaseCount,
    'without a release post: the edge does not own it')
assert(bodyIds()['body-22'] == nil and bodyIds()['body-23'].status == 'bound')
lease = { npc_id = npcId, entity_id = bodyIds()['body-23'].network_id }

local function runDeferred()
    local pending = deferred
    deferred = {}
    for _, thread in ipairs(pending) do thread() end
end
local function failedIn(reportAction)
    return reportAction and #reportAction.payload.failed or -1
end

deferSpawn = true
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 27, enabled = true,
    wanted = { planned('body-23', 7), planned('body-24', 7) }, released = {} }))
assert(#deferred == 1 and bodyIds()['body-24'].status == 'spawning')
assert(bodyIds()['body-24'].entity_id == nil, 'the body is still waiting for its spawn point')
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 28, enabled = true,
    wanted = { planned('body-23', 7) }, released = { 'body-24' } }))
assert(bodyIds()['body-24'].status == 'spawning', 'the plan alone leaves the pending spawn to the tick')
local createdCount, deletedCount, releaseCount = #created, #deleted, #actionsNamed('release_npc_body')
now = now + 31000
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('release_npc_body') == releaseCount + 1)
assert(lastAction('release_npc_body').payload.body_id == 'body-24')
assert(lastAction('release_npc_body').payload.cause == 'despawned',
    'a forgotten pending spawn is released with its cause')
assert(bodyIds()['body-24'] == nil, 'the record is gone')
assert(#deleted == deletedCount, 'there was no ped to delete')
assert(failedIn(lastAction('report_npc_bodies')) == 0, 'nothing is reported as failed')
runDeferred()
assert(#created == createdCount, 'the late spawn thread creates nothing')
assert(#actionsNamed('release_npc_body') == releaseCount + 1, 'and posts nothing more')
assert(bodyIds()['body-24'] == nil)

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 29, enabled = true,
    wanted = { planned('body-23', 7), planned('body-25', 7) }, released = {} }))
assert(#deferred == 1 and bodyIds()['body-25'].status == 'spawning')
reportResponse = { ok = true, unknown = { 'body-25' } }
HumalikeNpcPopulation.Report()
reportResponse = { ok = true }
assert(bodyIds()['body-25'].status == 'spawning', 'unknown marks a ped-less spawn for release')
releaseCount = #actionsNamed('release_npc_body')
now = now + 31000
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('release_npc_body') == releaseCount,
    'a forgotten pending spawn is dropped without a release post')
assert(bodyIds()['body-25'] == nil and #deleted == deletedCount)
assert(failedIn(lastAction('report_npc_bodies')) == 0)
runDeferred()
assert(#created == createdCount and bodyIds()['body-25'] == nil)

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 30, enabled = true,
    wanted = { planned('body-23', 7), planned('body-26', 7) }, released = {} }))
assert(#deferred == 1)
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 31, enabled = true,
    wanted = { planned('body-23', 7) }, released = { 'body-26' } }))
releaseCount = #actionsNamed('release_npc_body')
runDeferred()
assert(#created == createdCount, 'a spawn thread that wakes to a release creates nothing')
assert(#actionsNamed('release_npc_body') == releaseCount + 1)
assert(lastAction('release_npc_body').payload.body_id == 'body-26')
assert(lastAction('release_npc_body').payload.cause == 'despawned',
    'the spawn thread releases with the requested cause too')
assert(bodyIds()['body-26'] == nil)
HumalikeNpcPopulation.Reconcile()
assert(failedIn(lastAction('report_npc_bodies')) == 0)
deferSpawn = false
assert(bodyIds()['body-23'].status == 'bound')

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 32, enabled = true,
    wanted = { planned('body-23', 7), planned('body-30', 7) }, released = {} }))
local strangerPed = bodyIds()['body-30'].handle
entityState[strangerPed].humalike_body_id = 'someone-else'
deletedCount = #deleted
HumalikeNpcPopulation.Reconcile()
assert(#deleted == deletedCount, 'a handle that now belongs to another entity is not deleted')
assert(lastAction('release_npc_body').payload.body_id == 'body-30')
assert(lastAction('release_npc_body').payload.cause == 'despawned', 'the body counts as vanished')
assert(bodyIds()['body-30'] == nil)
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 33, enabled = true,
    wanted = { planned('body-23', 7), planned('body-31', 7) }, released = {} }))
strangerPed = bodyIds()['body-31'].handle
entityState[strangerPed].humalike_body_id = 'someone-else'
deletedCount = #deleted
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 34, enabled = true,
    wanted = { planned('body-23', 7) }, released = { 'body-31' } }))
assert(#deleted == deletedCount and bodyIds()['body-31'] == nil,
    'a despawn of a recycled handle does not delete the stranger')
existing[strangerPed] = nil

stateCount = #stateEvents()
deletedCount = #deleted
HumalikeNpcPopulation.Clear()
assert(HumalikeNpcPopulation.Enabled() == false)
assert(#stateEvents() == stateCount + 1 and stateEvents()[#stateEvents()].arg.enabled == false)
assert(#deleted == deletedCount + 1 and lastAction('release_npc_body').payload.body_id == 'body-23')
assert(lastAction('release_npc_body').payload.cause == 'despawned')
assert(next(bodyIds()) == nil or bodyIds()['body-8'] ~= nil, 'only the unanswered stop record can remain')
assert(bodyIds()['body-23'] == nil)
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 35, enabled = true,
    wanted = { planned('body-23', 7) }, released = {} }))
assert(#stateEvents() == stateCount + 2 and stateEvents()[#stateEvents()].arg.enabled == true,
    'the next plan enables the street again')
lease = { npc_id = npcId, entity_id = bodyIds()['body-23'].network_id }

holdReport = true
reportCount = #actionsNamed('report_npc_bodies')
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 36, enabled = true,
    wanted = { planned('body-23', 7) }, released = {} }))
assert(#actionsNamed('report_npc_bodies') == reportCount + 1 and type(pendingReport) == 'function')
assert(HumalikeNpcPopulation.Report() == false, 'a second report waits for the first')
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_npc_bodies') == reportCount + 1, 'the tick does not double-post either')
holdReport = false
local answer = pendingReport
pendingReport = nil
answer(true, 200, { ok = true })
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_npc_bodies') == reportCount + 2, 'the deferred report goes out once answered')

reportOk = false
reportCount = #actionsNamed('report_npc_bodies')
HumalikeNpcPopulation.Report()
assert(#actionsNamed('report_npc_bodies') == reportCount + 1)
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_npc_bodies') == reportCount + 1, 'no retry before the backoff')
now = now + 500
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_npc_bodies') == reportCount + 2, 'first retry after 500 ms')
now = now + 500
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_npc_bodies') == reportCount + 2, 'second retry waits 1000 ms')
now = now + 500
reportOk = true
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_npc_bodies') == reportCount + 3)
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_npc_bodies') == reportCount + 3, 'a delivered report is not repeated')

releaseOk = false
releaseCount = #actionsNamed('release_npc_body')
deletedCount = #deleted
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 37, enabled = true,
    wanted = {}, released = { 'body-23' } }))
assert(#deleted == deletedCount + 1 and #actionsNamed('release_npc_body') == releaseCount + 1)
assert(bodyIds()['body-23'].status == 'released')
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('release_npc_body') == releaseCount + 1, 'a rejected release waits for its backoff')
now = now + 500
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('release_npc_body') == releaseCount + 2)
now = now + 500
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('release_npc_body') == releaseCount + 2, 'the second retry waits twice as long')
for _ = 1, 10 do
    now = now + 31000
    HumalikeNpcPopulation.Reconcile()
end
assert(#actionsNamed('release_npc_body') == releaseCount + Config.Population.ReleaseMaxAttempts,
    'the release is posted at most ReleaseMaxAttempts times')
assert(bodyIds()['body-23'] == nil, 'then the record is dropped locally')
releaseOk = true

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 38, enabled = true,
    wanted = { planned('body-40', 7) }, released = {} }))
lease = { npc_id = npcId, entity_id = bodyIds()['body-40'].network_id }
assert(HumalikeNpcPopulation.Enabled() == true)
stateCount = #stateEvents()
reportOk = false
now = now + 31000
HumalikeNpcPopulation.Reconcile()
now = now + 31000
HumalikeNpcPopulation.Reconcile()
assert(#stateEvents() == stateCount and HumalikeNpcPopulation.Enabled() == true,
    'two silent heartbeats are tolerated')
now = now + 31000
HumalikeNpcPopulation.Reconcile()
assert(#stateEvents() == stateCount + 1 and stateEvents()[#stateEvents()].arg.enabled == false,
    'after three silent heartbeats GTA density and cops come back')
assert(HumalikeNpcPopulation.Enabled() == false)
assert(bodyIds()['body-40'].status == 'bound', 'the bodies are kept')
HumalikeNpcPopulation.Reconcile()
assert(#stateEvents() == stateCount + 1)
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 39, enabled = true,
    wanted = { planned('body-40', 7) }, released = {} }))
assert(#stateEvents() == stateCount + 2 and stateEvents()[#stateEvents()].arg.enabled == true,
    'the next accepted plan is contact and re-enables the street')
reportOk = true
now = now + 31000
HumalikeNpcPopulation.Reconcile()
now = now + 31000
HumalikeNpcPopulation.Reconcile()
now = now + 31000
HumalikeNpcPopulation.Reconcile()
assert(#stateEvents() == stateCount + 2 and HumalikeNpcPopulation.Enabled() == true,
    'answered heartbeat reports keep the street alive')

local lonely = planned('body-50', nil)
lonely.routing_bucket = 5
local eventCount = #clientEvents
assert(HumalikeNpcPopulation.ApplyPlan({ revision = 40, enabled = true,
    wanted = { planned('body-40', 7), lonely }, released = {} }))
local lonelyPed = bodyIds()['body-50'].handle
assert(lonelyPed and created[lonelyPed].x == 10 and created[lonelyPed].y == 0
    and created[lonelyPed].bucket == 5, 'with no player in the bucket the first candidate is used as is')
for index = eventCount + 1, #clientEvents do
    assert(clientEvents[index].name ~= 'humalike:npc:populationSpawnPoint', 'and no client is asked')
end

holdReport = true
reportCount = #actionsNamed('report_npc_bodies')
HumalikeNpcPopulation.Report()
local hung = pendingReport
pendingReport = nil
holdReport = false
now = now + Config.Population.RetryBackoffCapMs
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_npc_bodies') == reportCount + 1, 'still waiting inside the bound')
now = now + Config.Population.RetryBackoffCapMs + 1
HumalikeNpcPopulation.Reconcile()
assert(#actionsNamed('report_npc_bodies') == reportCount + 2, 'past the bound a fresh report goes out')
deletedCount = #deleted
hung(true, 200, { ok = true, unknown = { 'body-40' } })
assert(#deleted == deletedCount and bodyIds()['body-40'].status == 'bound',
    'a late answer to the abandoned report is ignored')

assert(HumalikeNpcPopulation.ApplyPlan({ revision = 41, enabled = true,
    wanted = { planned('body-40', 7), planned('body-41', 7) }, released = {} }))
local stopPeds = { bodyIds()['body-40'].handle, bodyIds()['body-41'].handle }
assert(stopPeds[1] and stopPeds[2])
noCredentials = true
deletedCount = #deleted
handlers['humalike:core:stopping']()
assert(#deleted == deletedCount + 2, 'both peds are deleted even though the release cannot be posted')
assert(existing[stopPeds[1]] == nil and existing[stopPeds[2]] == nil)
assert(bodyIds()['body-40'] == nil and bodyIds()['body-41'] == nil, 'the records are dropped at once')
handlers['onResourceStop']('humalike')
assert(#deleted == deletedCount + 2)
noCredentials = false

print('server_population: ok')
