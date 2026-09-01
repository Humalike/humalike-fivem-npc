
local SERVER_ACTION_EVENTS = {
    give_item = 'humalike:npc:runGiveItemAction',
    hand_over_money = 'humalike:npc:runHandOverMoneyAction',
}
local SERVER_ACTION_ANIMATIONS = {
    hand_over_money = true,
}

local function dispatchStaticAction(target, actionKey, params)
    local npc = NpcRegistry[target.npc_id]
    if not npc then
        HumalikeDebug('inbound push: unknown static npc %s, ignoring', target.npc_id)
        return false, 'unknown_static_npc'
    end
    local serverActionEvent = SERVER_ACTION_EVENTS[actionKey]
    if serverActionEvent then
        local entity = npc.entity_id
        if type(entity) ~= 'number' or entity <= 0 or not DoesEntityExist(entity)
            or GetEntityType(entity) ~= 1 or IsPedAPlayer(entity)
            or GetEntityHealth(entity) <= 0 then return false, 'static_entity_unavailable' end
        local playerId = params and params.player_id
        if type(playerId) ~= 'number' or playerId % 1 ~= 0 or playerId < 1
            or not GetPlayerName(playerId) then return false, 'invalid_action_player' end
        if GetPlayerRoutingBucket(playerId) ~= GetEntityRoutingBucket(entity) then
            return false, 'action_player_wrong_bucket'
        end
        local delivered = nil
        TriggerEvent(serverActionEvent, GetEntityCoords(entity), params or {}, function(result)
            delivered = result == true
        end)
        if delivered == nil then
            HumalikeDebug('inbound push: server action %q has no registered handler', actionKey)
            return false, 'action_handler_unavailable'
        end
        if delivered and SERVER_ACTION_ANIMATIONS[actionKey] then
            TriggerClientEvent('humalike:npc:playAction', -1, target.npc_id, actionKey, params or {})
        end
        return delivered, delivered and nil or 'action_rejected'
    end
    TriggerClientEvent('humalike:npc:playAction', -1, target.npc_id, actionKey, params or {})
    RecordNpcPose(target.npc_id, actionKey, target)
    return true
end

local function dispatchAmbientAction(target, actionKey, params)
    local lease, entity, reason = ValidateAmbientActionTarget(target)
    if not lease then return false, reason end
    local movementApplied, movementReason = HumalikeApplyAmbientMovementAction(
        target, lease, entity, actionKey, params or {})
    if movementApplied == false then return false, movementReason end
    local serverActionEvent = SERVER_ACTION_EVENTS[actionKey]
    if serverActionEvent then
        local playerId = params and params.player_id
        if type(playerId) ~= 'number' or playerId % 1 ~= 0 or playerId < 1
            or not GetPlayerName(playerId) then return false, 'invalid_action_player' end
        if GetPlayerRoutingBucket(playerId) ~= target.routing_bucket then
            return false, 'action_player_wrong_bucket'
        end
        local delivered = nil
        TriggerEvent(serverActionEvent, GetEntityCoords(entity), params or {}, function(result)
            delivered = result == true
        end)
        if delivered == nil then return false, 'action_handler_unavailable' end
        if delivered and SERVER_ACTION_ANIMATIONS[actionKey] then
            SendAmbientActionToOwner(target, entity, actionKey, params)
        end
        return delivered, delivered and nil or 'action_rejected'
    end
    if not SendAmbientActionToOwner(target, entity, actionKey, params)
        and movementApplied ~= true then
        return false, 'ambient_owner_unavailable'
    end
    RecordNpcPose(target.npc_id, actionKey, target)
    return true
end

local completedInvocations = {}
local MAX_COMPLETED_INVOCATIONS = 1024
local INVOCATION_TTL_SECONDS = 600

-- State-changing callbacks are at-least-once, so deduplicate by invocation ID.

local function invocationFingerprint(actionKey, target, params)
    return table.concat({
        actionKey,
        target.kind,
        target.npc_id,
        tostring(target.entity_id or ''),
        tostring(target.routing_bucket or ''),
        tostring(target.lease_token or ''),
        tostring(params.player_id or ''),
        tostring(params.item_name or ''),
        tostring(params.quantity or ''),
    }, '\0')
end

local function pruneInvocations(now)
    local count = 0
    local oldestId, oldestExpiry
    for invocationId, invocation in pairs(completedInvocations) do
        if invocation.expires_at <= now then
            completedInvocations[invocationId] = nil
        else
            count = count + 1
            if not oldestExpiry or invocation.expires_at < oldestExpiry then
                oldestId, oldestExpiry = invocationId, invocation.expires_at
            end
        end
    end
    if count >= MAX_COMPLETED_INVOCATIONS and oldestId then
        completedInvocations[oldestId] = nil
    end
end

local function dispatchAction(target, actionKey, params, invocationId)
    if not IsSupportedAction(actionKey) then return false, 'unsupported_action' end
    local deduped = SERVER_ACTION_EVENTS[actionKey] ~= nil
    local fingerprint
    if deduped then
        local now = os.time()
        pruneInvocations(now)
        fingerprint = invocationFingerprint(actionKey, target, params or {})
        local completed = completedInvocations[invocationId]
        if completed then
            if completed.fingerprint ~= fingerprint then return false, 'invocation_conflict' end
            return completed.result
        end
    end

    local delivered, reason
    if target.kind == 'static' then
        delivered, reason = dispatchStaticAction(target, actionKey, params)
    elseif target.kind == 'ambient' then
        delivered, reason = dispatchAmbientAction(target, actionKey, params)
    else
        return false, 'invalid_target_kind'
    end
    if deduped and delivered then
        completedInvocations[invocationId] = {
            result = true,
            fingerprint = fingerprint,
            expires_at = os.time() + INVOCATION_TTL_SECONDS,
        }
    end
    return delivered, reason
end
function HumalikeReleasePose(target)
    if type(target) ~= 'table' then return false end
    return dispatchAction(target, 'stand_up', {}, nil) == true
end

HumaLike.RegisterCallback('/roster-changed', function()
    HumalikeDebug('inbound push: roster changed, syncing now')
    SyncNpcRoster(nil, true)
    return 202, { ok = true }
end)

HumaLike.RegisterCallback('/clear-roster', function()
    HumalikeDebug('inbound push: clearing roster')
    HumalikeClearAmbientLeases()
    for npcId in pairs(NpcRegistry) do
        RemovePersistentNpc(npcId)
        NpcRegistry[npcId] = nil
        TriggerClientEvent('humalike:npc:removed', -1, npcId)
    end
    return 202, { ok = true }
end)

HumaLike.RegisterCallback('/ambient/candidates/validate', function(body)
    return 200, HumalikeValidateAmbientCandidates(body)
end)

HumaLike.RegisterCallback('/ambient/leases/validate', function(body)
    return 200, HumalikeValidateAmbientLeases(body)
end)

HumaLike.RegisterCallback('/ambient/leases', function(body)
    return 200, { ok = HumalikeApplyAmbientLeaseSnapshot(body) }
end)

HumaLike.RegisterCallback('/voice-mutes', function(body)
    local applied = HumalikeApplyVoiceMuteSnapshot(body)
    return applied and 200 or 409, { ok = applied }
end)

HumaLike.RegisterCallback('/action', function(body)
    local target = body.target
    if type(body.invocation_id) ~= 'string' or body.invocation_id == ''
        or #body.invocation_id > 128
        or type(target) ~= 'table' or type(target.kind) ~= 'string'
        or type(target.npc_id) ~= 'string' or target.npc_id == ''
        or type(body.action) ~= 'string' or body.action == ''
        or (body.params ~= nil and type(body.params) ~= 'table') then
        return 400, { ok = false, error = 'invalid_action' }
    end

    HumalikeDebug('inbound push: npc=%s kind=%s action=%s params=%s', target.npc_id,
        target.kind, body.action, json.encode(body.params or {}))
    local delivered, reason = dispatchAction(target, body.action, body.params,
        body.invocation_id)
    return 200, {
        ok = delivered,
        invocation_id = body.invocation_id,
        reason = delivered and nil or reason,
    }
end)
