Config = { PushSecretConvar = 'push_secret' }
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
function IsSupportedAction(action)
    return action == 'wave' or action == 'give_item' or action == 'hand_over_money'
        or action == 'hold_position' or action == 'release_movement'
end
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
function GetEntityCoords() return { x = 4, y = 5, z = 6 } end
function GetPlayerName(playerId) return playerId == 7 and 'Tester' or nil end
function GetPlayerRoutingBucket() return playerBucket end
function DoesEntityExist(entity) return entity == 201 and staticEntityExists end
function GetEntityType() return 1 end
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

dofile('server/inbound.lua')

local function request(body, auth, path)
    return handlers[path or '/action'](body)
end

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
assert(giveItemCalls == 2)

giveItem.params.quantity = 2
local _, conflict = request(giveItem)
assert(conflict.ok == false and conflict.reason == 'invocation_conflict')
assert(giveItemCalls == 2)
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
assert(request(robbery) == 200)
assert(handOverCalls == 1, 'a retried robbery does not pay twice')
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
assert(handOverCalls == 3)
assert(#clientEvents == ceAmbient + 1)
assert(clientEvents[#clientEvents].name == 'humalike:npc:playAmbientAction')

print('server_inbound: ok')
