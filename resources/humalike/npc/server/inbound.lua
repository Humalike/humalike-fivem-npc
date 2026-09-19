
local SERVER_ACTION_EVENTS = {
    give_item = 'humalike:npc:runGiveItemAction',
    hand_over_money = 'humalike:npc:runHandOverMoneyAction',
}
local SERVER_ACTION_ANIMATIONS = {
    hand_over_money = true,
}

local function staticEntity(npcId)
    local npc = NpcRegistry[npcId]
    if not npc then return nil, 'unknown_static_npc' end
    local entity = npc.entity_id
    if type(entity) ~= 'number' or entity <= 0 or not DoesEntityExist(entity)
        or GetEntityType(entity) ~= 1 or IsPedAPlayer(entity)
        or GetEntityHealth(entity) <= 0 then return nil, 'static_entity_unavailable' end
    return entity
end

local function actionPlayer(params, bucket)
    local playerId = params and params.player_id
    if type(playerId) ~= 'number' or playerId % 1 ~= 0 or playerId < 1
        or not GetPlayerName(playerId) then return nil, 'invalid_action_player' end
    if not HumalikePlayer.IsCharacterLoaded(playerId) then return nil, 'character_not_loaded' end
    if GetPlayerRoutingBucket(playerId) ~= bucket then return nil, 'action_player_wrong_bucket' end
    return playerId
end

local function dispatchStaticAction(target, actionKey, params)
    if not NpcRegistry[target.npc_id] then
        HumalikeDebug('inbound push: unknown static npc %s, ignoring', target.npc_id)
        return false, 'unknown_static_npc'
    end
    local serverActionEvent = SERVER_ACTION_EVENTS[actionKey]
    if serverActionEvent then
        local entity, reason = staticEntity(target.npc_id)
        if not entity then return false, reason end
        local playerId, playerReason = actionPlayer(params, GetEntityRoutingBucket(entity))
        if not playerId then return false, playerReason end
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
        if not delivered then return false, 'action_rejected' end
        return true
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
        local playerId, playerReason = actionPlayer(params, target.routing_bucket)
        if not playerId then return false, playerReason end
        local delivered = nil
        TriggerEvent(serverActionEvent, GetEntityCoords(entity), params or {}, function(result)
            delivered = result == true
        end)
        if delivered == nil then return false, 'action_handler_unavailable' end
        if delivered and SERVER_ACTION_ANIMATIONS[actionKey] then
            SendAmbientActionToOwner(target, entity, actionKey, params)
        end
        if not delivered then return false, 'action_rejected' end
        return true
    end
    if not SendAmbientActionToOwner(target, entity, actionKey, params)
        and movementApplied ~= true then
        return false, 'ambient_owner_unavailable'
    end
    RecordNpcPose(target.npc_id, actionKey, target)
    return true
end

-- Fixed values win over pushed params.
local function customParams(definition, params)
    local merged = { player_id = params.player_id }
    for name in pairs(definition.passthrough or {}) do
        if params[name] ~= nil then merged[name] = params[name] end
    end
    for name in pairs(definition.params_from or {}) do
        local value = params[name]
        if value == nil or not (type(value) == 'string' or type(value) == 'number'
            or type(value) == 'boolean') then
            return nil, ('missing_param:%s'):format(name)
        end
        merged[name] = value
    end
    for name, spec in pairs(definition.params) do
        local value = params[name]
        if value ~= nil then
            local valid = (spec.type == 'string' and type(value) == 'string')
                or (spec.type == 'integer' and math.type(value) == 'integer')
                or (spec.type == 'boolean' and type(value) == 'boolean')
            if valid and spec.enum then
                valid = false
                for _, choice in ipairs(spec.enum) do
                    if choice == value then valid = true break end
                end
            end
            if not valid then return nil, ('invalid_param:%s'):format(name) end
            merged[name] = value
        elseif spec.required then
            return nil, ('missing_param:%s'):format(name)
        end
    end
    for name, value in pairs(definition.fixed) do merged[name] = value end
    return merged
end

local function withinReach(playerId, npcCoords)
    local ped = GetPlayerPed(playerId)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local at = GetEntityCoords(ped)
    local dx, dy, dz = at.x - npcCoords.x, at.y - npcCoords.y, at.z - npcCoords.z
    return dx * dx + dy * dy + dz * dz <= Config.ServerActions.MaxDistance ^ 2
end

local function dispatchCustomAction(target, localKey, definition, params)
    local entity, bucket, reason
    if target.kind == 'static' then
        entity, reason = staticEntity(target.npc_id)
        if not entity then return false, reason end
        bucket = GetEntityRoutingBucket(entity)
    elseif target.kind == 'ambient' then
        local lease
        lease, entity, reason = ValidateAmbientActionTarget(target)
        if not lease then return false, reason end
        bucket = target.routing_bucket
    else
        return false, 'invalid_target_kind'
    end
    local playerId, playerReason = actionPlayer(params, bucket)
    if not playerId then return false, playerReason end
    local coords = GetEntityCoords(entity)
    if not withinReach(playerId, coords) then return false, 'action_player_out_of_reach' end
    local merged, paramsReason = customParams(definition, params or {})
    if not merged then return false, paramsReason end
    if not HumalikeActions.Run(localKey, playerId, coords, merged) then
        return false, 'action_rejected'
    end
    return true
end

-- State-changing callbacks are at-least-once, so deduplicate by invocation ID.
-- Only delivered ones are kept: a refusal is re-pushed under the same ID for up to an hour.
local completedInvocations = {}
local MAX_COMPLETED_INVOCATIONS = 4096
local INVOCATION_TTL_SECONDS = 6 * 3600

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
    if count > MAX_COMPLETED_INVOCATIONS and oldestId then
        completedInvocations[oldestId] = nil
    end
end

local function dispatchAction(target, actionKey, params, invocationId)
    if not IsSupportedAction(actionKey) then return false, 'unsupported_action' end
    local customKey, customDefinition = HumalikeActions.Custom(actionKey)
    local deduped = SERVER_ACTION_EVENTS[actionKey] ~= nil or customKey ~= nil
    if deduped then
        pruneInvocations(os.time())
        if completedInvocations[invocationId] then return true end
    end
    if HumalikeNpcRuntimeControl then
        local allowed, controlReason = HumalikeNpcRuntimeControl.AllowsAction(
            target.npc_id, actionKey)
        if not allowed then return false, controlReason end
    end

    local delivered, reason
    if customKey then
        delivered, reason = dispatchCustomAction(target, customKey, customDefinition, params)
    elseif target.kind == 'static' then
        delivered, reason = dispatchStaticAction(target, actionKey, params)
    elseif target.kind == 'ambient' then
        delivered, reason = dispatchAmbientAction(target, actionKey, params)
    else
        return false, 'invalid_target_kind'
    end
    if deduped and delivered then
        completedInvocations[invocationId] = { expires_at = os.time() + INVOCATION_TTL_SECONDS }
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
    if HumalikeNpcPopulation then HumalikeNpcPopulation.Clear() end
    for npcId in pairs(NpcRegistry) do
        RemovePersistentNpc(npcId)
        NpcRegistry[npcId] = nil
        TriggerClientEvent('humalike:npc:removed', -1, npcId)
    end
    return 202, { ok = true }
end)

HumaLike.RegisterCallback('/ambient/leases/validate', function(body)
    return 200, HumalikeValidateAmbientLeases(body)
end)

HumaLike.RegisterCallback('/ambient/leases', function(body)
    return 200, { ok = HumalikeApplyAmbientLeaseSnapshot(body) }
end)

HumaLike.RegisterCallback('/population/plan', function(body)
    local applied, reason = HumalikeNpcPopulation.ApplyPlan(body)
    if applied then return 200, { ok = true } end
    -- A stale revision is an out-of-order push, not a delivery failure.
    return reason == 'stale' and 409 or 400, { ok = false, reason = reason }
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
    local response = { ok = delivered == true, invocation_id = body.invocation_id }
    if not delivered then response.reason = reason end
    return 200, response
end)
