Config = {
    PushSecretConvar = 'push_secret', Integrations = {},
    SupportedActions = { 'wave', 'hand_over_money', 'hold_position', 'release_movement' },
    ServerActions = { MaxDistance = 5.0 },
}
NpcRegistry = { ['static-1'] = { npc_id = 'static-1', entity_id = 201, x = 1, y = 2, z = 3 } }

local handlers = {}
local secret = 'secret'
local nextBody
local clientEvents = {}
local giveItemCalls = 0
local playerBucket = 2
local staticEntityExists = true
local voiceMuteBody

json = {
    decode = function() return nextBody end,
    encode = function(value) return value end,
}

function GetConvar() return secret end
HumaLike = {
    RegisterCallback = function(path, callback) handlers[path] = callback end,
}
function HumalikeDebug() end
local printed, consolePrint = {}, print
function print(line) printed[#printed + 1] = line end
function GetCurrentResourceName() return 'humalike' end
function AddEventHandler() end
function exports() end
HumalikeInventory = { Available = function() return true end }
dofile('../server/core/text.lua')
dofile('../integration/server/registry.lua')
dofile('../integration/server/actions.lua')
-- The real actions provider: a declared deed and a shop, run by RunAction.
local runCalls, runResult = {}, true
local provider = {
    name = 'srp_actions', apiVersion = 1, priority = 10, SupportedActions = {}, Namespace = 'srp',
    Observations = { item_given = { fields = { item = 'string', quantity = 'integer' },
                                    template = { en = '{quantity} x {item}' } } },
    Actions = { give_map = {
        name = 'Give the map', description = 'Hand over the map.',
        params = { copies = { type = 'integer', enum = { 1, 2 } },
                   note = { type = 'string', required = true } },
        fixed = { item = 'treasure_map' },
        requires = { { observation = 'item_given', consume = true } },
        params_from = { paid = 'item_given.quantity' },
    } },
    Catalog = { currency = 'cash', payment = 'item_given',
                items = { water = { price = 5 }, bread = { price = 3 } } },
    RunAction = function(action, source, coords, params)
        runCalls[#runCalls + 1] = { action = action, source = source, coords = coords, params = params }
        if type(runResult) == 'function' then return runResult() end
        return runResult
    end,
}
function TriggerClientEvent(name, playerId, npcId, action, params)
    clientEvents[#clientEvents + 1] = {
        name = name,
        player_id = playerId,
        npc_id = npcId,
        action = action,
        params = params,
    }
end
local handOverCalls = 0
local handOverResult = true
function TriggerEvent(name, _, params, respond)
    if name == 'humalike:providers:changed' then return end
    if name == 'humalike:npc:runHandOverMoneyAction' then
        handOverCalls = handOverCalls + 1
        respond(handOverResult)
        return
    end
    assert(name == 'humalike:npc:runGiveItemAction')
    giveItemCalls = giveItemCalls + 1
    respond(true)
end
function ValidateAmbientActionTarget(target)
    if target.lease_token ~= 'lease-token' then return nil, nil, 'ambient_lease_expired' end
    return target, 101
end
local playerDistance = 0
function GetEntityCoords(entity)
    if entity == 700 then return { x = 4 + playerDistance, y = 5, z = 6 } end
    return { x = 4, y = 5, z = 6 }
end
function GetPlayerPed(playerId) return playerId == 7 and 700 or 0 end
function GetPlayerName(playerId) return playerId == 7 and 'Tester' or nil end
function GetPlayerRoutingBucket() return playerBucket end
function DoesEntityExist(entity) return entity == 700 or (entity == 201 and staticEntityExists) end
staticEntityIsPed = true
function GetEntityType() return staticEntityIsPed and 1 or 2 end
function IsPedAPlayer() return false end
function GetEntityHealth() return 100 end
function GetEntityRoutingBucket() return 2 end
function SendAmbientActionToOwner(target, _, action, params)
    clientEvents[#clientEvents + 1] = {
        name = 'humalike:npc:playAmbientAction',
        npc_id = target.npc_id,
        action = action,
        params = params,
    }
    return true
end
local movementActions = {}
function HumalikeApplyAmbientMovementAction(_, _, _, action, params)
    movementActions[#movementActions + 1] = { action = action, params = params }
    return action == 'hold_position' or action == 'release_movement' or nil
end
local recordedPoses = {}
function RecordNpcPose(npcId, actionKey)
    recordedPoses[#recordedPoses + 1] = { npc_id = npcId, action = actionKey }
end
function HumalikeApplyVoiceMuteSnapshot(body)
    voiceMuteBody = body
    return true
end
local blockedAction
HumalikeNpcRuntimeControl = {
    AllowsAction = function(_, action)
        if action == blockedAction then return false, 'npc_domain_controlled' end
        return true
    end,
}

local planRevision = 0
local populationCleared = 0
HumalikeNpcPopulation = {
    ApplyPlan = function(body)
        if type(body.revision) ~= 'number' then return false, 'invalid' end
        if body.revision <= planRevision then return false, 'stale' end
        planRevision = body.revision
        return true
    end,
    Clear = function() populationCleared = populationCleared + 1 end,
}
function HumalikeClearAmbientLeases() end
function RemovePersistentNpc() end

assert(HumalikeRegisterInternalProvider('actions', provider))
dofile('server/inbound.lua')

local function request(body, auth, path)
    return handlers[path or '/action'](body)
end

local planStatus, planResponse = request({ revision = 5, enabled = true }, nil, '/population/plan')
assert(planStatus == 200 and planResponse.ok == true)
planStatus, planResponse = request({ revision = 5, enabled = true }, nil, '/population/plan')
assert(planStatus == 409 and planResponse.ok == false and planResponse.reason == 'stale',
    'a stale plan revision is a conflict, not a delivery failure')
planStatus, planResponse = request({ enabled = true }, nil, '/population/plan')
assert(planStatus == 400 and planResponse.reason == 'invalid')

local muteStatus, muteResponse = request({ revision = 1, npcs = {} }, nil, '/voice-mutes')
assert(muteStatus == 200 and muteResponse.ok == true)
assert(voiceMuteBody.revision == 1)

local status = request({
    invocation_id = 'static-wave-1',
    target = { kind = 'static', npc_id = 'static-1' },
    action = 'wave',
    params = {},
})
assert(status == 200)
assert(#clientEvents == 1 and clientEvents[1].name == 'humalike:npc:playAction')

blockedAction = 'wave'
local _, controlled = request({
    invocation_id = 'static-wave-controlled',
    target = { kind = 'static', npc_id = 'static-1' },
    action = 'wave',
    params = {},
})
assert(controlled.ok == false and controlled.reason == 'npc_domain_controlled')
assert(#clientEvents == 1)
blockedAction = nil

status = request({ npc_id = 'static-1', action = 'wave', params = {} })
assert(status == 400)

status = request({
    invocation_id = 'ambient-wave-1',
    target = {
        kind = 'ambient',
        npc_id = 'ambient-1',
        entity_id = 101,
        routing_bucket = 2,
        lease_token = 'lease-token',
    },
    action = 'wave',
    params = {},
})
assert(status == 200)
assert(#clientEvents == 2 and clientEvents[2].name == 'humalike:npc:playAmbientAction')

local movementTarget = {
    kind = 'ambient', npc_id = 'ambient-1', entity_id = 101,
    routing_bucket = 2, lease_token = 'lease-token',
}
local _, held = request({
    invocation_id = 'ambient-hold-1', target = movementTarget,
    action = 'hold_position', params = { player_id = 7 },
})
assert(held.ok == true and movementActions[#movementActions].action == 'hold_position')
local _, released = request({
    invocation_id = 'ambient-release-1', target = movementTarget,
    action = 'release_movement', params = { player_id = 7 },
})
assert(released.ok == true and movementActions[#movementActions].action == 'release_movement')
assert(#recordedPoses == 4)
assert(recordedPoses[1].npc_id == 'static-1' and recordedPoses[1].action == 'wave')
assert(recordedPoses[2].npc_id == 'ambient-1' and recordedPoses[2].action == 'wave')
assert(recordedPoses[3].action == 'hold_position')
assert(recordedPoses[4].action == 'release_movement')

local ambientGiveItem = {
    invocation_id = 'ambient-give-item-1',
    target = {
        kind = 'ambient',
        npc_id = 'ambient-1',
        entity_id = 101,
        routing_bucket = 2,
        lease_token = 'lease-token',
    },
    action = 'give_item',
    params = { player_id = 7, item_name = 'water', quantity = 1 },
}
ambientGiveItem.params.player_id = 8
local _, invalidPlayer = request(ambientGiveItem)
assert(invalidPlayer.ok == false and invalidPlayer.reason == 'invalid_action_player')
assert(giveItemCalls == 0)
ambientGiveItem.params.player_id = 7
playerBucket = 3
local _, wrongBucket = request(ambientGiveItem)
assert(wrongBucket.ok == false and wrongBucket.reason == 'action_player_wrong_bucket')
assert(giveItemCalls == 0)
playerBucket = 2
assert(request(ambientGiveItem) == 200)
assert(giveItemCalls == 1)

local giveItem = {
    invocation_id = 'give-item-1',
    target = { kind = 'static', npc_id = 'static-1' },
    action = 'give_item',
    params = { player_id = 7, item_name = 'water', quantity = 1 },
}
staticEntityExists = false
local _, unavailable = request(giveItem)
assert(unavailable.ok == false and unavailable.reason == 'static_entity_unavailable')
assert(giveItemCalls == 1)
staticEntityExists = true
playerBucket = 3
local _, staticWrongBucket = request(giveItem)
assert(staticWrongBucket.ok == false and staticWrongBucket.reason == 'action_player_wrong_bucket')
assert(giveItemCalls == 1)
playerBucket = 2
assert(request(giveItem) == 200)
assert(request(giveItem) == 200)
assert(giveItemCalls == 2, 'the same invocation id is delivered once')
local posesBefore = #recordedPoses
local ceBefore = #clientEvents
local robbery = {
    invocation_id = 'robbery-1',
    target = { kind = 'static', npc_id = 'static-1' },
    action = 'hand_over_money',
    params = { player_id = 7, robber_description = 'czarna kominiarka' },
}
assert(request(robbery) == 200)
assert(handOverCalls == 1, 'payout dispatched once')
assert(#clientEvents == ceBefore + 1)
assert(clientEvents[#clientEvents].name == 'humalike:npc:playAction')
assert(clientEvents[#clientEvents].action == 'hand_over_money')
assert(#recordedPoses == posesBefore, 'a handover is not a remembered pose')
blockedAction = 'hand_over_money'
assert(request(robbery) == 200)
assert(handOverCalls == 1, 'a retried robbery does not pay twice')
blockedAction = nil
handOverResult = false
local ceReject = #clientEvents
local _, rejected = request({
    invocation_id = 'robbery-2',
    target = { kind = 'static', npc_id = 'static-1' },
    action = 'hand_over_money',
    params = { player_id = 7 },
})
assert(rejected.ok == false and rejected.reason == 'action_rejected')
assert(#clientEvents == ceReject, 'no gesture on a rejected payout')
handOverResult = true
assert(select(2, request({
    invocation_id = 'robbery-2',
    target = { kind = 'static', npc_id = 'static-1' },
    action = 'hand_over_money',
    params = { player_id = 7 },
})).ok == true, 'a refusal is not remembered: the same id is tried again')
assert(handOverCalls == 3)
local ceAmbient = #clientEvents
assert(request({
    invocation_id = 'robbery-ambient-1',
    target = {
        kind = 'ambient',
        npc_id = 'ambient-1',
        entity_id = 101,
        routing_bucket = 2,
        lease_token = 'lease-token',
    },
    action = 'hand_over_money',
    params = { player_id = 7, robber_description = 'x' },
}) == 200)
assert(handOverCalls == 4)
assert(#clientEvents == ceAmbient + 1)
assert(clientEvents[#clientEvents].name == 'humalike:npc:playAmbientAction')

-- A server-defined action: the model's values checked against the
-- declaration, the script's fixed values under them, one RunAction per
-- invocation id, and never the client animation path.
local ceCustom = #clientEvents
local function give(invocationId, params, target)
    return request({
        invocation_id = invocationId,
        target = target or { kind = 'static', npc_id = 'static-1' },
        action = 'srp:give_map',
        params = params,
    })
end
assert(select(2, give('map-0', { player_id = 7, copies = 2, note = 'here' })).reason == 'missing_param:paid')
local status, body = give('map-1', { player_id = 7, copies = 2, note = 'here', paid = 50 })
assert(status == 200 and body.ok == true, tostring(body.reason))
assert(runCalls[1].params.paid == 50)
assert(#runCalls == 1 and runCalls[1].action == 'give_map' and runCalls[1].source == 7)
assert(runCalls[1].coords.x == 4)
assert(runCalls[1].params.player_id == 7 and runCalls[1].params.copies == 2)
assert(runCalls[1].params.note == 'here' and runCalls[1].params.item == 'treasure_map')
assert(#clientEvents == ceCustom, 'no client animation for a server-defined action')
-- At-least-once delivery: the same invocation runs once.
assert(select(2, give('map-1', { player_id = 7, copies = 2, note = 'here', paid = 50 })).ok == true)
assert(#runCalls == 1)
-- Declared shape or nothing: a wrong enum value, a wrong type, a missing
-- required value, and a value the script never declared.
assert(select(2, give('map-2', { player_id = 7, copies = 3, note = 'x', paid = 50 })).reason == 'invalid_param:copies')
assert(select(2, give('map-3', { player_id = 7, copies = '2', note = 'x', paid = 50 })).reason == 'invalid_param:copies')
assert(select(2, give('map-4', { player_id = 7, paid = 50 })).reason == 'missing_param:note')
local _, extra = give('map-5', { player_id = 7, note = 'x', item = 'gold', hacked = true, paid = 50 })
assert(extra.ok == true and runCalls[#runCalls].params.hacked == nil)
assert(runCalls[#runCalls].params.item == 'treasure_map', 'fixed values always win')
assert(select(2, give('map-6', { player_id = 99, note = 'x', paid = 50 })).reason == 'invalid_action_player')
-- A stale static handle that now points at something else is no target.
staticEntityIsPed = false
assert(select(2, give('map-vehicle', { player_id = 7, note = 'x', paid = 50 })).reason == 'static_entity_unavailable')
staticEntityIsPed = true
-- Out of arm's reach, like the built-in hand-overs.
playerDistance = 5.5
assert(select(2, give('map-far', { player_id = 7, note = 'x', paid = 50 })).reason == 'action_player_out_of_reach')
playerDistance = 0
-- The script may still refuse; a refusal is retried under the same id, and
-- only exactly `true` is a deed done: a throw, a 1, a nil all reject.
local map7 = { player_id = 7, note = 'x', paid = 50 }
runResult = false
assert(select(2, give('map-7', map7)).reason == 'action_rejected')
local runsBefore = #runCalls
assert(select(2, give('map-7', map7)).reason == 'action_rejected')
assert(#runCalls == runsBefore + 1, 'a refused deed runs again on the retry')
runResult = function() error('inventory offline') end
assert(select(2, give('map-7', map7)).reason == 'action_rejected')
assert(printed[#printed]:find('RunAction failed: .*inventory offline'), printed[#printed])
runResult = 1
assert(select(2, give('map-7', map7)).reason == 'action_rejected')
assert(printed[#printed]:find('RunAction%(give_map%) returned number'), printed[#printed])
runResult = 'ok'
local warnings = #printed
assert(select(2, give('map-7', map7)).reason == 'action_rejected')
assert(#printed == warnings, 'the return-type warning is said once')
runResult = nil
assert(select(2, give('map-7', map7)).reason == 'action_rejected')
runResult = true
assert(select(2, give('map-7', map7)).ok == true)
assert(select(2, give('map-7', map7)).ok == true and #runCalls == runsBefore + 6,
    'once done, the id is remembered')
-- An ambient body needs its live lease like any other deed.
assert(select(2, give('map-8', { player_id = 7, note = 'x', paid = 50 }, {
    kind = 'ambient', npc_id = 'ambient-1', entity_id = 101, routing_bucket = 2,
    lease_token = 'stale',
})).reason == 'ambient_lease_expired')
assert(select(2, give('map-9', { player_id = 7, note = 'x', paid = 50 }, {
    kind = 'ambient', npc_id = 'ambient-1', entity_id = 101, routing_bucket = 2,
    lease_token = 'lease-token',
})).ok == true)

-- The counter's basket reaches the script as HumaLike sent it.
local _, basket = request({
    invocation_id = 'order-1', target = { kind = 'static', npc_id = 'static-1' },
    action = 'srp:deliver',
    params = { player_id = 7, items = { water = 2, bread = 1 }, total = 13, paid = 15, change = 2,
               currency = 'cash', hacked = true },
})
assert(basket.ok == true, tostring(basket.reason))
local delivered = runCalls[#runCalls]
assert(delivered.action == 'deliver' and delivered.params.items.water == 2)
assert(delivered.params.change == 2 and delivered.params.currency == 'cash')
assert(delivered.params.hacked == nil)
-- The same order pushed again (a lost response) is a fresh decode of the
-- same basket: delivered once.
local _, again = request({
    invocation_id = 'order-1', target = { kind = 'static', npc_id = 'static-1' },
    action = 'srp:deliver',
    params = { player_id = 7, items = { water = 2, bread = 1 }, total = 13, paid = 15, change = 2,
               currency = 'cash' },
})
assert(again.ok == true and runCalls[#runCalls] == delivered)
-- No provider, no deed.
assert(HumalikeProviders.registered.actions.srp_actions)
HumalikeProviders.registered.actions.srp_actions = nil
HumalikeProviders.selected.actions = nil
assert(select(2, give('map-none', map7)).reason == 'unsupported_action')

assert(request({}, nil, '/clear-roster') == 202)
assert(populationCleared == 1, 'clearing the roster clears the population too')

consolePrint('server_inbound: ok')
