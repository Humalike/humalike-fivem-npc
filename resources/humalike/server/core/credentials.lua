HumaLike = HumaLike or {}

local runtime = nil
local leaseKvp = 'humalike:runtime:lease:v1'

local function validCredential(value)
    return type(value) == 'string' and #value >= 32
end

local function validIdentifier(value)
    return type(value) == 'string' and value ~= '' and #value <= 128
end

local function validUuid(value)
    if type(value) ~= 'string' or #value ~= 36 then return false end
    if value:sub(9, 9) ~= '-'
        or value:sub(14, 14) ~= '-'
        or value:sub(19, 19) ~= '-'
        or value:sub(24, 24) ~= '-' then return false end
    local compact = value:gsub('-', '')
    return #compact == 32 and compact:match('^%x+$') ~= nil
end

function HumaLike.PreviousRuntimeLeaseId()
    if type(GetResourceKvpString) ~= 'function' then return nil end
    local value = GetResourceKvpString(leaseKvp)
    return validIdentifier(value) and value or nil
end

local function validCallbackCredential(value)
    return type(value) == 'table'
        and validCredential(value.token)
        and type(value.valid_from_unix) == 'number'
        and type(value.valid_until_unix) == 'number'
        and value.valid_from_unix < value.valid_until_unix
end

local function validAssignment(assignmentId, nodeId, nodeBootId, generation)
    return validUuid(assignmentId)
        and validIdentifier(nodeId)
        and nodeId:match('^%S+$') ~= nil
        and validUuid(nodeBootId)
        and type(generation) == 'number'
        and generation >= 1
        and generation % 1 == 0
end

function HumaLike.ReplaceRuntimeCredentials(payload, expectedBootId)
    local now = os.time()
    if type(payload) ~= 'table'
        or not validIdentifier(payload.server_id)
        or not validIdentifier(payload.boot_id)
        or not validIdentifier(payload.lease_id)
        or (expectedBootId ~= nil and payload.boot_id ~= expectedBootId)
        or not validCredential(payload.edge_access_token)
        or not validCredential(payload.voice_access_token)
        or type(payload.access_tokens_expire_at) ~= 'string'
        or payload.access_tokens_expire_at == ''
        or type(payload.edge_url) ~= 'string'
        or not payload.edge_url:match('^https?://')
        or not validAssignment(
            payload.edge_assignment_id,
            payload.edge_node_id,
            payload.edge_boot_id,
            payload.edge_generation)
        or type(payload.voice_url) ~= 'string'
        or not payload.voice_url:match('^https?://')
        or not validAssignment(
            payload.voice_assignment_id,
            payload.voice_node_id,
            payload.voice_boot_id,
            payload.voice_generation)
        or not validCallbackCredential(payload.callback_current)
        or not validCallbackCredential(payload.callback_next)
        or payload.callback_current.valid_from_unix > now + 60
        or payload.callback_next.valid_from_unix
            ~= payload.callback_current.valid_until_unix
        or payload.callback_next.valid_until_unix <= payload.callback_current.valid_until_unix
        or payload.callback_current.valid_until_unix <= now then
        return false, 'bootstrap returned malformed credentials'
    end

    runtime = {
        serverId = payload.server_id,
        bootId = payload.boot_id,
        leaseId = payload.lease_id,
        edgeToken = payload.edge_access_token,
        edgeUrl = payload.edge_url,
        edgeAssignmentId = payload.edge_assignment_id,
        edgeNodeId = payload.edge_node_id,
        edgeBootId = payload.edge_boot_id,
        edgeGeneration = payload.edge_generation,
        voiceToken = payload.voice_access_token,
        expiresAt = payload.access_tokens_expire_at,
        voiceUrl = payload.voice_url,
        voiceAssignmentId = payload.voice_assignment_id,
        voiceNodeId = payload.voice_node_id,
        voiceBootId = payload.voice_boot_id,
        voiceGeneration = payload.voice_generation,
        callbackCurrent = payload.callback_current,
        callbackNext = payload.callback_next
    }
    if type(SetResourceKvp) == 'function' then
        SetResourceKvp(leaseKvp, payload.lease_id)
    end
    return true
end

function HumaLike.RuntimeCredentials()
    return runtime
end

function HumaLike.ClearRuntimeCredentials()
    runtime = nil
end
