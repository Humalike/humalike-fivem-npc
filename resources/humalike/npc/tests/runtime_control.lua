local exported, handlers, clientEvents, posts = {}, {}, {}, {}
local owner = 'mission-one'
local now = 1000
local cleanupThread
local ambientToken = 'ambient-token-1'
local forgottenPoses = {}
local entityStates = {
    [101] = { humalike_action = { key = 'follow_player', params = { player_id = 7 } } },
    [202] = { humalike_action = { key = 'kneel', params = {} } },
    [303] = {},
}
source = 7

NpcRegistry = {
    ['static-1'] = {
        npc_id = 'static-1', type = 'static', entity_id = 101, network_id = 51,
        routing_bucket = 2,
    },
    ['external-1'] = {
        npc_id = 'external-1', type = 'external', entity_id = 303, network_id = 53,
        routing_bucket = 4,
    },
    ['external-offline'] = {
        npc_id = 'external-offline', type = 'external', routing_bucket = 0,
    },
}

function exports(name, callback) exported[name] = callback end
function GetInvokingResource() return owner end
function GetCurrentResourceName() return 'humalike' end
function GetGameTimer() return now end
function DoesEntityExist(entity) return entity == 101 or entity == 202 or entity == 303 end
function GetEntityRoutingBucket(entity)
    if entity == 101 then return 2 end
    return entity == 202 and 3 or 4
end
function GetEntityModel(entity) return entity == 101 and 10 or entity == 202 and 20 or 30 end
function NetworkGetNetworkIdFromEntity(entity) return entity == 303 and 53 or 0 end
function RegisterNetEvent() end
function AddEventHandler(name, callback) handlers[name] = callback end
function TriggerClientEvent(name, target, revision, controls)
    clientEvents[#clientEvents + 1] = {
        name = name, target = target, revision = revision, controls = controls,
    }
end
function CreateThread(callback) cleanupThread = callback end
function Wait() coroutine.yield() end
function SetTimeout(_, callback) callback() end
function Entity(entity)
    local state = entityStates[entity]
    state.set = function(_, key, value) state[key] = value end
    return { state = state }
end
function ForgetNpcPose(npcId) forgottenPoses[#forgottenPoses + 1] = npcId end
function HumalikeFindAmbientLease(npcId)
    if npcId == 'ambient-1' then
        return {
            npc_id = npcId, entity_handle = 202, entity_id = 52, network_id = 52,
            routing_bucket = 3, lease_token = ambientToken,
        }
    end
end
HumaLike = {
    RuntimeCredentials = function() return { bootId = 'boot-1' } end,
}
HumalikeNpcEntityOwnership = {
    ExternalEntity = function(npcId) return npcId == 'external-1' and 303 or nil end,
    SuppressedStaticNpcIds = function() return { 'static-offline' } end,
    State = function(npcId)
        return npcId == 'external-1' and { entityOwner = 'external', bindingId = 'binding-1' }
            or { entityOwner = 'humalike' }
    end,
}
HumalikeHttp = {
    PostAction = function(name, body, callback)
        posts[#posts + 1] = { name = name, body = body }
        callback(true)
    end,
}

dofile('../server/core/export_result.lua')
dofile('server/runtime_state.lua')
dofile('server/runtime_control.lua')

local function success(result)
    assert(result.apiVersion == 1 and result.ok == true and result.error == nil)
    return result.value
end

local function failure(result, expected)
    assert(result.apiVersion == 1 and result.ok == false and result.error == expected)
    assert(result.value == nil)
end

local state = success(exported.GetNpcRuntimeState('static-1'))
assert(state.kind == 'static' and state.active == true and state.networkId == 51)
local externalState = success(exported.GetNpcRuntimeState('external-1'))
assert(externalState.kind == 'external' and externalState.active == true)
assert(externalState.networkId == 53 and externalState.bindingId == 'binding-1')
local offlineState = success(exported.GetNpcRuntimeState('external-offline'))
assert(offlineState.kind == 'external' and offlineState.active == false)
assert(offlineState.aiEnabled == false)
failure(exported.AcquireNpcControl('external-offline', { domains = { 'speech' } }),
    'npc_not_active')

local lease = success(exported.AcquireNpcControl('static-1', {
    domains = { 'movement', 'animation' }, ttlMs = 30000, reason = 'mission',
}))
assert(lease.ownerResource == 'mission-one' and lease.expiresInMs == 30000)
assert(posts[#posts].name == 'sync_npc_runtime_state')
assert(posts[#posts].body.controls[1].npc_id == 'static-1')
assert(posts[#posts].body.suppressed_static_npc_ids[1] == 'static-offline')
assert(clientEvents[#clientEvents].controls['static-1'].movement == true)
assert(entityStates[101].humalike_action == nil, 'takeover stops sustained HumaLike actions')
assert(forgottenPoses[#forgottenPoses] == 'static-1', 'animation takeover forgets replayable poses')

local controlled = success(exported.GetNpcRuntimeState('static-1'))
assert(controlled.controlledDomains.movement.ownerResource == 'mission-one')
assert(HumalikeNpcRuntimeControl.AllowsAction('static-1', 'follow_player') == false)
assert(HumalikeNpcRuntimeControl.AllowsAction('static-1', 'wave') == false)
assert(HumalikeNpcRuntimeControl.AllowsAction('static-1', 'give_item') == true)

failure(exported.AcquireNpcControl('static-1', {
    domains = { 'movement' }, ttlMs = 1000,
}), 'domain_conflict')
failure(exported.AcquireNpcControl('ambient-1', {
    domains = { 'all', 'speech' }, ttlMs = 1000,
}), 'all_domain_must_be_exclusive')

owner = 'mission-two'
failure(exported.ReleaseNpcControl(lease.id), 'not_owner')
owner = 'mission-one'
assert(success(exported.RenewNpcControl(lease.id, 5000)).expiresInMs == 5000)
assert(exported.ReleaseNpcControl(lease.id).ok == true)
assert(HumalikeNpcRuntimeControl.AllowsAction('static-1', 'follow_player') == true)

local ambient = success(exported.AcquireNpcControl('ambient-1', {
    domains = { 'all' }, ttlMs = 1000,
}))
assert(ambient.kind == 'ambient')
assert(HumalikeNpcRuntimeControl.AllowsAction('ambient-1', 'give_item') == false)
assert(entityStates[202].humalike_action == nil, 'all takeover also stops ambient actions')
handlers.onResourceStop('mission-one')
assert(HumalikeNpcRuntimeControl.AllowsAction('ambient-1', 'give_item') == true)

local incarnated = success(exported.AcquireNpcControl('ambient-1', {
    domains = { 'movement' }, ttlMs = 1000,
}))
ambientToken = 'ambient-token-2'
local cleanup = coroutine.create(cleanupThread)
assert(coroutine.resume(cleanup))
assert(coroutine.resume(cleanup))
assert(HumalikeNpcRuntimeControl.AllowsAction('ambient-1', 'follow_player') == true)
failure(exported.ReleaseNpcControl(incarnated.id), 'lease_not_found')

owner = nil
failure(exported.AcquireNpcControl('static-1', { domains = { 'speech' } }),
    'external_resource_required')

handlers['humalike:npc:requestRuntimeControls']()
assert(clientEvents[#clientEvents].target == 7)
assert(type(cleanupThread) == 'function')

local retryTimers = {}
owner = 'mission-one'
SetTimeout = function(_, callback) retryTimers[#retryTimers + 1] = callback end
HumalikeHttp.PostAction = function(name, body, callback)
    posts[#posts + 1] = { name = name, body = body }
    callback(false)
end
local postsBeforeRetry = #posts
assert(exported.AcquireNpcControl('static-1', {
    domains = { 'speech' }, ttlMs = 1000,
}).ok)
assert(#retryTimers == 1)
assert(exported.AcquireNpcControl('static-1', {
    domains = { 'perception' }, ttlMs = 1000,
}).ok)
assert(#retryTimers == 2 and #posts == postsBeforeRetry + 2)
HumalikeHttp.PostAction = function(name, body, callback)
    posts[#posts + 1] = { name = name, body = body }
    callback(true)
end
retryTimers[1]()
assert(#posts == postsBeforeRetry + 2, 'superseded retry timer is inert')
retryTimers[2]()
assert(#posts == postsBeforeRetry + 3 and #retryTimers == 2,
    'only the latest snapshot retry reaches edge')

print('runtime_control: ok')
