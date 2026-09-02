local exported, handlers, clientEvents, posts = {}, {}, {}, {}
local owner = 'mission-one'
local now = 1000
local cleanupThread
local ambientToken = 'ambient-token-1'
source = 7

NpcRegistry = {
    ['static-1'] = {
        npc_id = 'static-1', entity_id = 101, network_id = 51, routing_bucket = 2,
    },
}

function exports(name, callback) exported[name] = callback end
function GetInvokingResource() return owner end
function GetCurrentResourceName() return 'humalike' end
function GetGameTimer() return now end
function DoesEntityExist(entity) return entity == 101 or entity == 202 end
function GetEntityRoutingBucket(entity) return entity == 101 and 2 or 3 end
function GetEntityModel(entity) return entity == 101 and 10 or 20 end
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
HumalikeHttp = {
    PostAction = function(name, body, callback)
        posts[#posts + 1] = { name = name, body = body }
        callback(true)
    end,
}

dofile('server/runtime_control.lua')

local state = assert(exported.GetNpcRuntimeState('static-1'))
assert(state.kind == 'static' and state.active == true and state.networkId == 51)

local lease = assert(exported.AcquireNpcControl('static-1', {
    domains = { 'movement', 'animation' }, ttlMs = 30000, reason = 'mission',
}))
assert(lease.ownerResource == 'mission-one' and lease.expiresInMs == 30000)
assert(posts[#posts].name == 'sync_npc_runtime_controls')
assert(posts[#posts].body.npcs[1].npc_id == 'static-1')
assert(clientEvents[#clientEvents].controls['static-1'].movement == true)

local controlled = assert(exported.GetNpcRuntimeState('static-1'))
assert(controlled.controlledDomains.movement.ownerResource == 'mission-one')
assert(HumalikeNpcRuntimeControl.AllowsAction('static-1', 'follow_player') == false)
assert(HumalikeNpcRuntimeControl.AllowsAction('static-1', 'wave') == false)
assert(HumalikeNpcRuntimeControl.AllowsAction('static-1', 'give_item') == true)

local _, conflict = exported.AcquireNpcControl('static-1', {
    domains = { 'movement' }, ttlMs = 1000,
})
assert(conflict == 'domain_conflict')
local _, invalidAll = exported.AcquireNpcControl('ambient-1', {
    domains = { 'all', 'speech' }, ttlMs = 1000,
})
assert(invalidAll == 'all_domain_must_be_exclusive')

owner = 'mission-two'
local released, releaseError = exported.ReleaseNpcControl(lease.id)
assert(released == false and releaseError == 'not_owner')
owner = 'mission-one'
assert(exported.RenewNpcControl(lease.id, 5000).expiresInMs == 5000)
assert(exported.ReleaseNpcControl(lease.id) == true)
assert(HumalikeNpcRuntimeControl.AllowsAction('static-1', 'follow_player') == true)

local ambient = assert(exported.AcquireNpcControl('ambient-1', {
    domains = { 'all' }, ttlMs = 1000,
}))
assert(ambient.kind == 'ambient')
assert(HumalikeNpcRuntimeControl.AllowsAction('ambient-1', 'give_item') == false)
handlers.onResourceStop('mission-one')
assert(HumalikeNpcRuntimeControl.AllowsAction('ambient-1', 'give_item') == true)

local incarnated = assert(exported.AcquireNpcControl('ambient-1', {
    domains = { 'movement' }, ttlMs = 1000,
}))
ambientToken = 'ambient-token-2'
local cleanup = coroutine.create(cleanupThread)
assert(coroutine.resume(cleanup))
assert(coroutine.resume(cleanup))
assert(HumalikeNpcRuntimeControl.AllowsAction('ambient-1', 'follow_player') == true)
assert(exported.ReleaseNpcControl(incarnated.id) == false)

owner = nil
local _, ownerError = exported.AcquireNpcControl('static-1', { domains = { 'speech' } })
assert(ownerError == 'external_resource_required')

handlers['humalike:npc:requestRuntimeControls']()
assert(clientEvents[#clientEvents].target == 7)
assert(type(cleanupThread) == 'function')

print('runtime_control: ok')
