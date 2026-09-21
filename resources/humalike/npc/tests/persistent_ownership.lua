local created, posts, timers, handlers = 0, {}, {}, {}
local mode = 'external'
local entityStates = { [202] = {}, [303] = {} }
local assignment = 'edge-a:7'

HumaLike = {
    RuntimeCredentials = function()
        return { bootId = 'boot-1' }
    end,
    EdgeAssignmentKey = function() return assignment end,
    IsCurrentEdgeAssignment = function(expected) return expected == assignment end,
}
HumalikeNpcEntityOwnership = {
    ExternalEntity = function() return mode == 'external' and 202 or nil end,
    IsDespawned = function() return mode == 'despawned' end,
    SetRuntimeToken = function() end,
    Reconcile = function() end,
}
HumalikeHttp = {
    PostAction = function(name, body, callback)
        posts[#posts + 1] = { name = name, body = body }
        callback(true, 200, { runtime_token = 'token' })
    end,
}

function NetworkGetNetworkIdFromEntity(entity) return entity == 202 and 52 or 53 end
function NetworkGetEntityOwner() return 7 end
function GetEntityRoutingBucket() return 0 end
function GetEntityModel() return 10 end
function DoesEntityExist(entity) return entity == 202 or entity == 303 end
function CreatePed()
    created = created + 1
    return 303
end
function SetEntityRoutingBucket() end
function SetEntityOrphanMode() end
function GetHashKey() return 10 end
function Entity(entity)
    local state = entityStates[entity]
    state.set = function(_, key, value) state[key] = value end
    return { state = state }
end
function TriggerClientEvent() end
function CreateThread() end
function AddEventHandler(name, callback) handlers[name] = callback end
function Wait() end
function DeleteEntity() end
function SetTimeout(_, callback) timers[#timers + 1] = callback end

dofile('server/persistent.lua')

local external = { npc_id = 'external-1', type = 'external', model = 'model-one' }
assert(EnsurePersistentNpc(external) == 202)
assert(created == 0 and external.entity_id == 202 and external.network_id == 52)
assert(entityStates[202].humalike_npc_id == 'external-1')
assert(entityStates[202].humalike_position_reporter == 7)
assert(posts[#posts].name == 'upsert_npc_runtime_binding')

local delayedCallback
HumalikeHttp.PostAction = function(name, body, callback)
    posts[#posts + 1] = { name = name, body = body }
    if name == 'upsert_npc_runtime_binding' then
        delayedCallback = callback
    else
        callback(true, 200, { removed = true })
    end
end
local delayed = { npc_id = 'external-delayed', type = 'external', model = 'model-one' }
RegisterPersistentNpcBinding(delayed, 202)
mode = 'managed'
delayedCallback(true, 200, { runtime_token = 'late-token' })
assert(posts[#posts].name == 'remove_npc_runtime_binding')
assert(posts[#posts].body.runtime_token == 'late-token')

mode = 'managed'
assert(EnsurePersistentNpc(external) == nil)
assert(external.entity_id == nil and external.network_id == nil and external.runtime_token == nil)

local entry = { npc_id = 'static-1', type = 'static', model = 'model-one' }
assert(EnsurePersistentNpc(entry) == 303)
assert(created == 1 and PersistentNpcEntities['static-1'] == 303)
delayedCallback(true, 200, { runtime_token = 'static-token' })

local removalCallback
HumalikeHttp.PostAction = function(name, body, callback)
    posts[#posts + 1] = { name = name, body = body }
    if name == 'remove_npc_runtime_binding' then
        removalCallback = callback
    else
        callback(true, 200, { runtime_token = 'replacement-token' })
    end
end
RemovePersistentNpcRuntimeBinding('static-1', 'old-token')
local postsBeforeDeferredBinding = #posts
RegisterPersistentNpcBinding(entry, 303)
assert(#posts == postsBeforeDeferredBinding, 'rebind waits for pending removal')
removalCallback(true, 200, { removed = true })
assert(posts[#posts].name == 'upsert_npc_runtime_binding')

local attempts = 0
HumalikeHttp.PostAction = function(name, body, callback)
    attempts = attempts + 1
    posts[#posts + 1] = { name = name, body = body }
    callback(attempts >= 2, attempts >= 2 and 200 or 503, { removed = attempts >= 2 })
end
RemovePersistentNpcRuntimeBinding('static-1', 'old-token')
assert(#timers == 1 and attempts == 1)
assert(posts[#posts].body.boot_id == 'boot-1')
timers[1]()
assert(attempts == 2)

HumaLike.RuntimeCredentials = function() return nil end
RemovePersistentNpcRuntimeBinding('static-1', 'offline-token')
assert(#timers == 2 and attempts == 2)
HumaLike.RuntimeCredentials = function() return { bootId = 'boot-2' } end
timers[2]()
assert(posts[#posts].body.boot_id == 'boot-2')

local staleCallback
HumalikeHttp.PostAction = function(name, body, callback)
    posts[#posts + 1] = { name = name, body = body }
    staleCallback = callback
end
NpcRegistry = { ['static-1'] = entry }
entry.runtime_token = nil
RegisterPersistentNpcBinding(entry, 303)
local oldAssignmentCallback = staleCallback
assignment = 'edge-b:8'
handlers['humalike:runtime:edgeChanged']({ generation = 8 })
oldAssignmentCallback(true, 200, { runtime_token = 'stale-edge-token' })
assert(entry.runtime_token ~= 'stale-edge-token',
    'a stale binding response must not mutate the current NPC')
assert(posts[#posts].name == 'upsert_npc_runtime_binding',
    'a stale binding response must replay the binding on the current edge')
local currentCallback = staleCallback
local replacementEntry = {
    npc_id = 'static-1', type = 'static', model = 'model-one',
    entity_id = 303, network_id = 53,
}
NpcRegistry['static-1'] = replacementEntry
currentCallback(true, 200, { runtime_token = 'current-edge-token' })
assert(replacementEntry.runtime_token == 'current-edge-token',
    'a binding response must update the current roster entry')

local refreshBindingCallbacks = {}
HumalikeHttp.PostAction = function(name, body, callback)
    posts[#posts + 1] = { name = name, body = body }
    if name == 'upsert_npc_runtime_binding' then
        refreshBindingCallbacks[#refreshBindingCallbacks + 1] = callback
    end
end
RegisterPersistentNpcBinding(replacementEntry, 303)
handlers['humalike:runtime:refreshed']({ edgeChanged = false })
assert(#refreshBindingCallbacks == 2,
    'credential refresh must supersede an in-flight binding request')
refreshBindingCallbacks[1](true, 200, { runtime_token = 'old-credential-token' })
assert(replacementEntry.runtime_token ~= 'old-credential-token')
refreshBindingCallbacks[2](true, 200, { runtime_token = 'refreshed-credential-token' })
assert(replacementEntry.runtime_token == 'refreshed-credential-token')

local staleRemovalCallback
HumalikeHttp.PostAction = function(name, body, callback)
    posts[#posts + 1] = { name = name, body = body }
    if name == 'remove_npc_runtime_binding' then staleRemovalCallback = callback end
end
RemovePersistentNpcRuntimeBinding('static-1', 'edge-b-token')
assignment = 'edge-c:9'
handlers['humalike:runtime:edgeChanged']({ generation = 9 })
assert(posts[#posts].name == 'upsert_npc_runtime_binding',
    'old-assignment removal work must not block rebinding on the new edge')
staleRemovalCallback(true, 200, { removed = true })

local refreshRemovalCallbacks = {}
HumalikeHttp.PostAction = function(name, body, callback)
    posts[#posts + 1] = { name = name, body = body }
    if name == 'remove_npc_runtime_binding' then
        refreshRemovalCallbacks[#refreshRemovalCallbacks + 1] = callback
    elseif name == 'upsert_npc_runtime_binding' then
        callback(true, 200, { runtime_token = 'edge-c-token' })
    end
end
RemovePersistentNpcRuntimeBinding('external-1', 'edge-c-old-token')
refreshRemovalCallbacks[1](false, 401, {})
handlers['humalike:runtime:refreshed']({ edgeChanged = false })
assert(#refreshRemovalCallbacks == 2,
    'credential refresh must immediately retry pending removal on the same edge')
refreshRemovalCallbacks[2](true, 200, { removed = true })

print('persistent_ownership: ok')
