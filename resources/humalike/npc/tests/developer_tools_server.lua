local command
local handlers = {}
local threads = {}
local actions = {}
local deleted = {}
local clientEvents = {}
local entityState = {}
local leaseBucket = 2
local aceAllowed = true
local releaseResponse = { released = true }
local deliverReleaseResponse = true
local assignment = 'edge-a:7'
local delayBinding = false
local bindingCallbacks = {}

HumaLike = {
    EdgeAssignmentKey = function() return assignment end,
    IsCurrentEdgeAssignment = function(expected) return expected == assignment end,
}

function GetConvar() return '1' end
function RegisterCommand(_, callback) command = callback end
function RegisterNetEvent() end
function AddEventHandler(name, callback) handlers[name] = callback end
function CreateThread(callback) threads[#threads + 1] = callback end
function IsPlayerAceAllowed() return aceAllowed end
function GetPlayerName() return 'Tester' end
function TriggerClientEvent(...)
    clientEvents[#clientEvents + 1] = { ... }
end
function GetPlayerPed() return 700 end
function GetPlayerRoutingBucket() return 2 end
function DoesEntityExist(entity) return entity == 700 or entity == 101 end
function GetEntityCoords(entity)
    return entity == 700 and { x = 10, y = 20, z = 30 } or { x = 13, y = 20, z = 30 }
end
function GetEntityHeading() return 90 end
function CreatePed() return 101 end
function GetHashKey() return 123 end
function SetEntityRoutingBucket() end
function SetEntityOrphanMode() end
function NetworkGetNetworkIdFromEntity() return 55 end
function GetEntityModel() return 123 end
function GetGameTimer() return 456 end
function Wait() end
function DeleteEntity(entity) deleted[#deleted + 1] = entity end
function GetCurrentResourceName() return 'humalike' end
function Entity(entity)
    entityState[entity] = entityState[entity] or {}
    return { state = setmetatable({
        set = function(_, key, value) entityState[entity][key] = value end,
    }, { __index = entityState[entity] }) }
end

local npcId = '12345678-1234-1234-1234-123456789abc'
function HumalikeFindAmbientLease()
    return {
        npc_id = npcId,
        entity_id = 55,
        network_id = 55,
        entity_handle = 101,
        routing_bucket = leaseBucket,
    }
end

HumalikeHttp = {
    PostAction = function(name, payload, callback)
        actions[#actions + 1] = { name = name, payload = payload }
        if not callback then return end
        if name == 'prepare_ambient_debug_spawn' then
            callback(true, 200, {
                status = 'ready', npc_id = npcId, model = 'a_m_m_business_01', model_hash = 123,
            })
        elseif name == 'bind_ambient_debug_spawn' then
            if delayBinding then
                bindingCallbacks[#bindingCallbacks + 1] = callback
            else
                callback(true, 200, { status = 'bound', npc_id = npcId, entity_id = 101 })
            end
        elseif name == 'release_ambient_debug_spawn' then
            if deliverReleaseResponse then callback(true, 200, releaseResponse) end
        end
    end,
}

dofile('server/developer_tools.lua')

assert(type(command) == 'function')
command(7, { 'ambient', 'spawn', npcId })
assert(actions[1].name == 'prepare_ambient_debug_spawn')
assert(actions[2].name == 'bind_ambient_debug_spawn')
assert(actions[2].payload.npc_id == npcId)
assert(actions[2].payload.entity_id == 55)
assert(entityState[101].humalike_debug_spawn_id ~= nil)

local actionCount = #actions
command(7, { 'ambient', 'spawn', npcId })
assert(#actions == actionCount)
local existingReply = clientEvents[#clientEvents]
assert(existingReply[1] == 'humalike:npc:developerReply')
assert(existingReply[3]:find('already leased:', 1, true))
assert(existingReply[3]:find('already leased: coords=', 1, true))
assert(existingReply[3]:find('entity=101', 1, true))
assert(existingReply[3]:find('network=55', 1, true))
assert(existingReply[3]:find('coords=(13.00, 20.00, 30.00)', 1, true))

command(7, { 'ambient', 'goto', npcId })
local gotoEvent = clientEvents[#clientEvents]
assert(gotoEvent[1] == 'humalike:npc:developerGotoAmbient')
assert(gotoEvent[2] == 7 and gotoEvent[3] == 55)

leaseBucket = 3
command(7, { 'ambient', 'goto', npcId })
local refusal = clientEvents[#clientEvents]
assert(refusal[1] == 'humalike:npc:developerReply')

command(7, { 'ambient', 'remove', npcId })
assert(actions[#actions].name == 'release_ambient_debug_spawn')
assert(deleted[1] == 101)
command(7, { 'ambient', 'spawn', npcId })
releaseResponse = { released = false, reason = 'not_owned' }
command(7, { 'ambient', 'remove', npcId })
assert(deleted[2] == 101)
local alreadyGoneReply = clientEvents[#clientEvents]
assert(alreadyGoneReply[3]:find('removed debug spawn', 1, true))
delayBinding = true
command(7, { 'ambient', 'spawn', npcId })
local staleBinding = bindingCallbacks[1]
assignment = 'edge-b:8'
handlers['humalike:runtime:edgeChanged']({ generation = 8 })
assert(#bindingCallbacks == 2, 'edge change must replay active debug-spawn bindings')
local repliesBeforeBinding = #clientEvents
staleBinding(true, 200, { status = 'bound' })
assert(#clientEvents == repliesBeforeBinding,
    'stale debug-spawn binding response must not mutate current state')
bindingCallbacks[2](true, 200, { status = 'bound' })
assert(#clientEvents == repliesBeforeBinding + 1)
delayBinding = false
deliverReleaseResponse = false
handlers['onResourceStop']('humalike')
assert(deleted[3] == 101)

actionCount = #actions
command(7, { 'ambient', 'spawn', 'not-a-uuid' })
assert(#actions == actionCount)

aceAllowed = false
command(7, { 'ambient', 'list' })
assert(#actions == actionCount)

-- observe: typed from the declaration, replies with the rendered line or the
-- export's rejection code.
aceAllowed = true
local reported = {}
HumalikeActions = {
    Observation = function(key)
        if key ~= 'item_given' then return nil end
        return 'srp:item_given', { fields = { item = 'string', quantity = 'integer', stolen = 'boolean' } }
    end,
}
function HumalikeReportObservation(npcId, playerId, key, fields)
    reported[#reported + 1] = { npcId = npcId, playerId = playerId, key = key, fields = fields }
    if fields.item == nil then return { ok = false, error = 'invalid_field:item' } end
    return { ok = true, value = { key = 'srp:' .. key, text = 'handed you ' .. fields.item } }
end
local function lastReply()
    local event = clientEvents[#clientEvents]
    return event[1] == 'humalike:npc:developerReply' and event[3] or nil
end

command(7, { 'observe', 'not-a-uuid', 'item_given' })
assert(#reported == 0 and lastReply() == '[humalike-dev] a canonical NPC UUID is required')
command(7, { 'observe', npcId, 'door_unlocked' })
assert(#reported == 0 and lastReply() == '[humalike-dev] unknown observation door_unlocked')
command(7, { 'observe', npcId, 'item_given', 'item=amulet', 'quantity=2', 'stolen=true' })
assert(reported[1].npcId == npcId and reported[1].playerId == 7 and reported[1].key == 'item_given')
assert(reported[1].fields.item == 'amulet' and reported[1].fields.quantity == 2
    and reported[1].fields.stolen == true)
assert(lastReply() == '[humalike-dev] reported srp:item_given: handed you amulet', lastReply())
command(7, { 'observe', npcId, 'item_given', 'quantity=2' })
assert(lastReply() == '[humalike-dev] observation rejected: invalid_field:item')
command(7, { 'observe', npcId, 'item_given', 'item=amulet', 'stolen=tru' })
assert(#reported == 2 and lastReply() == '[humalike-dev] stolen must be true or false')
print('developer_tools_server (observe): ok')
