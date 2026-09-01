HumalikeWorldContracts = {}

local function finite(value)
    return type(value) == 'number' and value == value and value > -math.huge and value < math.huge
end

function HumalikeWorldContracts.Vec3(value)
    if type(value) ~= 'table' or not finite(value.x)
        or not finite(value.y) or not finite(value.z) then return nil end
    return { x = value.x + 0.0, y = value.y + 0.0, z = value.z + 0.0 }
end

function HumalikeWorldContracts.NpcRegistration(value)
    if type(value) ~= 'table' or type(value.npcId) ~= 'string'
        or value.npcId == '' or #value.npcId > 64 then return nil, 'invalid npcId' end
    local entity = tonumber(value.entity)
    if not entity or entity <= 0 then return nil, 'invalid entity' end
    local registration = {
        v = 1,
        npcId = value.npcId,
        entity = entity,
        entityId = tonumber(value.entityId),
        networkId = tonumber(value.networkId),
        modelHash = tonumber(value.modelHash),
        runtimeToken = value.runtimeToken,
        kind = value.kind or 'persistent',
        activity = value.activity or 'idle',
        ownerResource = value.ownerResource or 'unknown',
    }
    if registration.modelHash and registration.modelHash < 0 then
        registration.modelHash = registration.modelHash + 4294967296
    end
    if registration.modelHash and (registration.modelHash % 1 ~= 0
        or registration.modelHash < 0 or registration.modelHash > 4294967295) then
        return nil, 'invalid modelHash'
    end
    if type(registration.runtimeToken) ~= 'string' or registration.runtimeToken == ''
        or #registration.runtimeToken > 128 then return nil, 'invalid runtimeToken' end
    if registration.kind ~= 'persistent' and registration.kind ~= 'ambient' then
        return nil, 'invalid kind'
    end
    return registration
end

function HumalikeWorldContracts.Copy(value)
    if type(value) ~= 'table' then return value end
    local copy = {}
    for key, item in pairs(value) do copy[key] = HumalikeWorldContracts.Copy(item) end
    return copy
end
