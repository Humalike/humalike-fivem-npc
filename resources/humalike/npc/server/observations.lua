-- Server observations: facts an integration reports about its own NPC.
--
-- The script declares what it can observe on its actions provider
-- (`Namespace` + `Observations`, validated at RegisterProvider) and reports
-- each occurrence here. The line the NPC reads is rendered from the declared
-- template in that NPC's language before it leaves the box, so the backend
-- quotes it verbatim and never needs the declarations.

local STRING_LIMIT = 64

local function cleanString(value)
    if type(value) ~= 'string' or value:find('%c') then return nil end
    value = value:match('^%s*(.-)%s*$')
    local length = utf8.len(value)
    if value == '' or not length or length > STRING_LIMIT then return nil end
    return value
end

local FIELD_CHECKS = {
    string = cleanString,
    integer = function(value)
        if type(value) ~= 'number' or value % 1 ~= 0 or value ~= value then return nil end
        return math.tointeger(value)
    end,
    number = function(value)
        if type(value) ~= 'number' or value ~= value or value == math.huge
            or value == -math.huge then return nil end
        return value
    end,
    boolean = function(value)
        if type(value) ~= 'boolean' then return nil end
        return value
    end,
}

-- Every declared field, exactly, with its declared type: the template and,
-- later, an action's preconditions both read these by name.
local function validatedFields(definition, raw)
    raw = raw or {}
    if type(raw) ~= 'table' then return nil, 'invalid_fields' end
    local fields = {}
    for name, fieldType in pairs(definition.fields) do
        local value = FIELD_CHECKS[fieldType](raw[name])
        if value == nil then return nil, ('invalid_field:%s'):format(name) end
        fields[name] = value
    end
    for name in pairs(raw) do
        if definition.fields[name] == nil then return nil, ('unknown_field:%s'):format(name) end
    end
    return fields
end

local function formatValue(value)
    if math.type(value) == 'float' and value % 1 == 0 then return ('%d'):format(value) end
    return tostring(value)
end

local function render(definition, language, fields)
    local template = definition.template[language] or definition.template.en
    if not template then
        local _, first = next(definition.template)
        template = first
    end
    return (template:gsub('{([^{}]*)}', function(name) return formatValue(fields[name]) end))
end

-- Whose fact this is: a roster NPC (static, or external and bound) or an
-- ambient body the server currently leases. The backend re-checks ownership;
-- this only spares the round trip for an NPC nobody here has heard of.
local function resolveTarget(npcId)
    if type(npcId) ~= 'string' then return nil end
    local entry = NpcRegistry and NpcRegistry[npcId]
    if entry then return { language = entry.language } end
    local lease = HumalikeFindAmbientLease and HumalikeFindAmbientLease(npcId) or nil
    if lease then return { language = lease.language, lease_token = lease.lease_token } end
    return nil
end

function HumalikeReportObservation(npcId, playerId, key, rawFields, options)
    playerId = tonumber(playerId)
    if not playerId or playerId <= 0 or playerId % 1 ~= 0 then
        return HumalikeExportResult.Failure('invalid_player')
    end
    if not HumalikePlayer.IsCharacterLoaded(playerId) then
        return HumalikeExportResult.Failure('character_not_loaded')
    end
    local target = resolveTarget(npcId)
    if not target then return HumalikeExportResult.Failure('npc_not_found') end
    local wireKey, definition = HumalikeActions.Observation(key)
    if not definition then return HumalikeExportResult.Failure('unknown_observation') end
    local fields, err = validatedFields(definition, rawFields)
    if not fields then return HumalikeExportResult.Failure(err) end
    options = options or {}
    if type(options) ~= 'table' or (options.react ~= nil and type(options.react) ~= 'boolean') then
        return HumalikeExportResult.Failure('invalid_options')
    end
    local text = render(definition, target.language, fields)
    HumalikePostPlayerEvent(playerId, {
        type = 'server_observation',
        npc_id = npcId,
        lease_token = target.lease_token,
        key = wireKey,
        text = text,
        -- An empty Lua table encodes as a JSON array; the contract defaults
        -- the field, so an observation without fields simply omits it.
        fields = next(fields) ~= nil and fields or nil,
        react = options.react ~= false,
    })
    HumalikeDebug('observation %s for npc %s from player %d: %s', wireKey, npcId, playerId, text)
    return HumalikeExportResult.Success({ key = wireKey, text = text })
end

exports('ReportObservation', function(npcId, playerId, key, fields, options)
    return HumalikeReportObservation(npcId, playerId, key, fields, options)
end)

-- An order is addressed the way a fact is (orders.lua).
HumalikeObservationTarget = resolveTarget
