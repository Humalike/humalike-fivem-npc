Config = {
    AmbientLeaseScopeDistance = 200,
    AmbientLeaseScopeTickMs = 2000,
    AmbientControl = {
        InteractionDistance = 3,
        ServerValidationDistance = 4.5,
        ReleaseDistance = 30,
        RequestCooldownMs = 750,
    },
    AmbientRevive = {
        InteractionDistance = 3,
        DurationMs = 5000,
        CompletionToleranceMs = 500,
        SessionTimeoutMs = 10000,
    },
}

local handlers = {}
local threads = {}
local clientPayload
local clientControl
local actionEvent
local muteSnapshot
local entityState = {}
local entityOwner = 7

HumalikePlayer = { IsCharacterLoaded = function() return true end }
source = 7

function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
function CreateThread(handler) threads[#threads + 1] = handler end
function Wait() error('stop thread') end
function GetGameTimer() return 2000 end
function GetPlayerPed() return 700 end
function GetPlayerRoutingBucket() return 2 end
function GetEntityRoutingBucket(entity)
    return (entity == 101 or entity == 102 or entity == 103 or entity == 105) and 2 or 0
end
function NetworkDoesEntityExistWithNetworkId(networkId)
    return networkId == 53 or networkId == 54 or networkId == 55 or networkId == 57
end
function NetworkGetEntityFromNetworkId(networkId)
    return ({ [53] = 101, [54] = 102, [55] = 103, [57] = 105 })[networkId] or 0
end
function NetworkGetNetworkIdFromEntity(entity) return entity == 101 and 53 or 0 end
function NetworkGetEntityOwner(entity) return entity == 101 and entityOwner or -1 end
function DoesEntityExist(entity)
    return entity == 700 or entity == 101 or entity == 102 or entity == 103 or entity == 105
end
function GetEntityType() return 1 end
function IsPedAPlayer() return false end
playerCoords = { x = 0, y = 0, z = 0 }
function GetEntityCoords(entity)
    if entity == 700 then return playerCoords end
    return { x = 1, y = 2, z = 3 }
end
function GetEntityModel() return 123 end
function GetEntityHeading() return 90 end
function GetEntityHealth(entity) return entity == 103 and 0 or 100 end
function GetVehiclePedIsIn(entity) return (entity == 102 or entity == 105) and 200 or 0 end
function GetPlayers() return { '7' } end
function GetPlayerName(playerId) return tonumber(playerId) == 7 and 'Tester' or nil end
function Entity(entity)
    entityState[entity] = entityState[entity] or {}
    return { state = setmetatable({
        set = function(_, key, value) entityState[entity][key] = value end,
    }, { __index = entityState[entity] }) }
end
leaseSends = 0
function TriggerClientEvent(name, playerId, payload, entityId, leaseToken, actionKey, params)
    if name == 'humalike:npc:ambientLeases' then
        clientPayload = payload
        leaseSends = leaseSends + 1
    end
    if name == 'humalike:npc:ambientControlChanged' then
        clientControl = { key = payload, control = entityId }
    end
    if name == 'humalike:npc:playAmbientAction' then
        actionEvent = {
            player_id = playerId,
            npc_id = payload,
            entity_id = entityId,
            lease_token = leaseToken,
            action = actionKey,
            params = params,
        }
    end
    if name == 'humalike:npc:voiceMuteSnapshot' then
        muteSnapshot = { revision = payload, states = entityId }
    end
end
function HumalikeDebug() end

local pendingTimeouts = {}
function SetTimeout(_delayMs, callback) pendingTimeouts[#pendingTimeouts + 1] = callback end
local function runPendingTimeouts()
    local due = pendingTimeouts
    pendingTimeouts = {}
    for _, callback in ipairs(due) do callback() end
end

NpcRegistry = {
    ['static-1'] = { npc_id = 'static-1', voice_muted = false },
}

dofile('server/pose_ledger.lua') -- loaded before ambient.lua by the manifest
dofile('server/ambient.lua')
assert(HumalikeApplyAmbientLeaseSnapshot({
    revision = 1,
    enabled = true,
    leases = {
        {
            entity_id = 53,
            routing_bucket = 2,
            npc_id = 'ambient-1',
            lease_token = 'lease-token',
            display_name = 'Jarek',
            language = 'en',
            expires_in_seconds = 15,
            voice_active = true,
            voice_muted = true,
        },
        {
            entity_id = 54,
            routing_bucket = 2,
            npc_id = 'ambient-rider',
            lease_token = 'in-vehicle',
            display_name = 'Passenger',
            expires_in_seconds = 15,
        },
    },
}))
assert(clientPayload and #clientPayload.leases == 2)
assert(clientPayload.discovery_radius == nil and clientPayload.lease_ttl_seconds == nil,
    'the client payload carries no discovery fields')
assert(clientPayload.leases[1].network_id == 53)
assert(clientPayload.leases[1].entity_id == 53)
assert(clientPayload.leases[1].language == 'en')
assert(AmbientNpcLeases[101].npc_id == 'ambient-1')
assert(entityState[101].humalike_position_reporter == 7)
assert(HumalikeApplyVoiceMuteSnapshot({
    revision = 1,
    npcs = {
        { npc_id = 'static-1', voice_muted = true },
        { npc_id = 'ambient-1', voice_muted = true },
    },
}))
assert(NpcRegistry['static-1'].voice_muted == true)
assert(muteSnapshot.revision == 1 and muteSnapshot.states['ambient-1'] == true)
assert(not HumalikeApplyVoiceMuteSnapshot({ revision = 1, npcs = {} }))
handlers['humalike:npc:setAmbientControl'](53, 'ambient-1', 'lease-token', 'held')
assert(clientControl and clientControl.key == '53')
assert(clientControl.control and clientControl.control.mode == 'held')

local lease, entity = ValidateAmbientActionTarget({
    kind = 'ambient',
    npc_id = 'ambient-1',
    entity_id = 53,
    routing_bucket = 2,
    lease_token = 'lease-token',
})
assert(lease and entity == 101)
assert(HumalikeApplyAmbientMovementAction({ entity_id = 53 }, lease, entity,
    'release_movement', { player_id = 7 }) == true)
assert(clientControl.control == nil)
assert(entityState[101].humalike_action == nil)
assert(HumalikeApplyAmbientMovementAction({ entity_id = 53 }, lease, entity,
    'hold_position', { player_id = 7 }) == true)
assert(clientControl.control and clientControl.control.mode == 'held')
assert(clientControl.control.controller_source == 7)
assert(HumalikeApplyAmbientMovementAction({ entity_id = 53 }, lease, entity,
    'follow_player', { player_id = 7 }) == nil)
assert(clientControl.control == nil, 'follow must release hold before it starts')
local invalidMovement, invalidMovementReason = HumalikeApplyAmbientMovementAction(
    { entity_id = 53 }, lease, entity, 'hold_position', { player_id = 8 })
assert(invalidMovement == false and invalidMovementReason == 'invalid_action_player')
local invalidLease, _, invalidReason = ValidateAmbientActionTarget({
    kind = 'ambient',
    npc_id = 'ambient-1',
    entity_id = 53,
    routing_bucket = 2,
    lease_token = 'stale-token',
})
assert(invalidLease == nil and invalidReason == 'ambient_lease_expired')

assert(SendAmbientActionToOwner({
    npc_id = 'ambient-1',
    entity_id = 53,
    routing_bucket = 2,
    lease_token = 'lease-token',
}, 101, 'wave', {}))
assert(actionEvent and actionEvent.player_id == 7)
assert(actionEvent.npc_id == 'ambient-1' and actionEvent.entity_id == 53)
assert(actionEvent.lease_token == 'lease-token' and actionEvent.action == 'wave')
entityOwner = -1
assert(not SendAmbientActionToOwner({ routing_bucket = 2 }, 101, 'wave', {}))
clientPayload = nil
handlers['humalike:npc:requestAmbientLeaseSnapshot']()
assert(clientPayload and #clientPayload.leases == 2)
assert(clientPayload.leases[1].voice_muted == true)
assert(clientPayload.leases[1].language == 'en')
local validation = HumalikeValidateAmbientLeases({ leases = {
    { entity_id = 53, model_hash = 123, routing_bucket = 2, lease_token = 'lease-token' },
    { entity_id = 54, model_hash = 123, routing_bucket = 2, lease_token = 'in-vehicle' },
    { entity_id = 54, model_hash = 123, routing_bucket = 2, lease_token = 'wrong-token' },
    { entity_id = 55, model_hash = 123, routing_bucket = 2, lease_token = 'dead' },
    { entity_id = 56, model_hash = 123, routing_bucket = 2, lease_token = 'gone' },
    { entity_id = 57, model_hash = 123, routing_bucket = 2, lease_token = 'not-active' },
} })
assert(#validation.valid == 3)
assert(validation.valid[1].entity_id == 53 and validation.valid[2].entity_id == 54
    and validation.valid[3].entity_id == 55)
assert(#validation.invalid_entity_ids == 3)
assert(validation.invalid_entity_ids[1] == 54
    and validation.invalid_entity_ids[2] == 56
    and validation.invalid_entity_ids[3] == 57)
assert(#validation.invalid_leases == 3)
assert(validation.invalid_leases[1].entity_id == 54
    and validation.invalid_leases[1].reason == 'vehicle')
assert(validation.invalid_leases[2].entity_id == 56
    and validation.invalid_leases[2].reason == 'missing')
assert(validation.invalid_leases[3].entity_id == 57
    and validation.invalid_leases[3].reason == 'vehicle')

assert(HumalikeApplyAmbientLeaseSnapshot({ revision = 2, enabled = true, leases = {} }))
assert(AmbientNpcLeases[101] == nil)
assert(entityState[101].humalike_position_reporter == nil)

assert(HumalikeApplyAmbientLeaseSnapshot({
    revision = 3,
    enabled = true,
    leases = {
        {
            entity_id = 53,
            routing_bucket = 2,
            npc_id = 'ambient-1',
            lease_token = 'lease-token-2',
            display_name = 'Jarek',
            expires_in_seconds = 15,
        },
    },
}))
HumalikeClearAmbientLeases()
assert(AmbientNpcLeases[101] == nil)
assert(clientPayload.enabled == false and #clientPayload.leases == 0)
entityOwner = 7
actionEvent = nil
NpcPoses['ambient-1'] = 'kneel'
assert(HumalikeApplyAmbientLeaseSnapshot({
    revision = 5,
    enabled = true,
    leases = {
        {
            entity_id = 53,
            routing_bucket = 2,
            npc_id = 'ambient-1',
            lease_token = 'lease-token-3',
            display_name = 'Jarek',
            expires_in_seconds = 15,
        },
    },
}))
assert(actionEvent == nil) -- nothing replays until the delay elapses
runPendingTimeouts()
assert(actionEvent and actionEvent.npc_id == 'ambient-1' and actionEvent.action == 'kneel')
assert(actionEvent.lease_token == 'lease-token-3')
actionEvent = nil
assert(HumalikeApplyAmbientLeaseSnapshot({
    revision = 6,
    enabled = true,
    leases = {
        {
            entity_id = 53,
            routing_bucket = 2,
            npc_id = 'ambient-1',
            lease_token = 'lease-token-3',
            display_name = 'Jarek',
            expires_in_seconds = 15,
        },
    },
}))
runPendingTimeouts()
assert(actionEvent == nil)
actionEvent = nil
entityOwner = -1 -- no valid owner yet: SendAmbientActionToOwner returns false
assert(HumalikeApplyAmbientLeaseSnapshot({
    revision = 7,
    enabled = true,
    leases = {
        {
            entity_id = 53,
            routing_bucket = 2,
            npc_id = 'ambient-1',
            lease_token = 'lease-token-4',
            display_name = 'Jarek',
            expires_in_seconds = 15,
        },
    },
}))
runPendingTimeouts()
assert(actionEvent == nil)
entityOwner = 7 -- client bound the lease; the next attempt lands
runPendingTimeouts()
assert(actionEvent and actionEvent.action == 'kneel')
assert(actionEvent.lease_token == 'lease-token-4')
actionEvent = nil
entityOwner = -1
assert(HumalikeApplyAmbientLeaseSnapshot({
    revision = 8,
    enabled = true,
    leases = {
        {
            entity_id = 53,
            routing_bucket = 2,
            npc_id = 'ambient-1',
            lease_token = 'lease-token-5',
            display_name = 'Jarek',
            expires_in_seconds = 15,
        },
    },
}))
runPendingTimeouts()
RecordNpcPose('ambient-1', 'stand_up')
entityOwner = 7
runPendingTimeouts()
assert(actionEvent == nil)
assert(NpcPoses['ambient-1'] == nil)
local scopedSnapshot = {
    revision = 100,
    enabled = true,
    leases = {
        {
            entity_id = 53,
            routing_bucket = 2,
            npc_id = 'ambient-1',
            lease_token = 'scoped-token',
            display_name = 'Jarek',
            language = 'en',
            expires_in_seconds = 15,
        },
    },
}

playerCoords = { x = 5000, y = 0, z = 0 } -- far from the ped at (1, 2, 3)
leaseSends = 0
assert(HumalikeApplyAmbientLeaseSnapshot(scopedSnapshot))
assert(leaseSends == 1 and #clientPayload.leases == 0, 'a distant lease is not this player\'s business')

scopedSnapshot.revision = 101
assert(HumalikeApplyAmbientLeaseSnapshot(scopedSnapshot))
assert(leaseSends == 1, 'an unchanged slice must not cost a packet')

playerCoords = { x = 0, y = 0, z = 0 } -- walks back into range
local scopeTick = threads[#threads - 1] -- the ownership-reporter loop is last
local function runOneTick()
    local waits = 0
    Wait = function()
        waits = waits + 1
        if waits > 1 then error('stop thread') end
    end
    pcall(scopeTick)
end
runOneTick()
assert(leaseSends == 2 and #clientPayload.leases == 1, 'walking into range binds the lease')
assert(clientPayload.leases[1].npc_id == 'ambient-1')

runOneTick()
assert(leaseSends == 2, 'a tick that finds nothing new sends nothing')
handlers['humalike:npc:requestAmbientLeaseSnapshot']()
assert(leaseSends == 2, 'the request cooldown still applies')

print('server_ambient: ok')
