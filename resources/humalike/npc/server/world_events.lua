
local SIMPLE_EVENTS = {
    doj_badge_shown = true,
    ems_badge_shown = true,
    hands_lowered = true,
    hands_raised = true,
    police_badge_shown = true,
}

local function send(observation, delay, attempt)
    attempt = attempt or 1
    HumalikeHttp.PostAction('ingest_world_event', observation, function(ok, status, body)
        local accepted = ok and body and body.ok == true
        if type(HumalikeDebug) == 'function' then
            HumalikeDebug('world event player=%s type=%s kind=%s accepted=%s status=%s attempt=%d',
                tostring(observation.fivem_session_id), tostring(observation.event.type),
                tostring(observation.event.kind), tostring(accepted), tostring(status), attempt)
        end
        if accepted then return end
        if attempt < 5 and (status == 0 or status >= 500) then
            SetTimeout(delay, function() send(observation, delay * 2, attempt + 1) end)
        end
    end)
end

function HumalikePostPlayerEvent(playerId, event)
    send({
        fivem_session_id = playerId,
        source_event_id = HumalikeHttp.NextSourceEventId(playerId),
        occurred_at = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        event = event,
    }, 1000)
end

local function cleanText(value, maxLength)
    if type(value) ~= 'string' or value:find('%c') then return nil end
    value = value:match('^%s*(.-)%s*$')
    local length = utf8.len(value)
    if value == '' or not length or length > maxLength then return nil end
    return value
end

local function validatedEvent(value)
    if type(value) ~= 'table' or type(value.type) ~= 'string' then return nil end
    if SIMPLE_EVENTS[value.type] then return { type = value.type } end
    if value.type == 'rp_action' then
        if value.kind ~= 'me' and value.kind ~= 'do' then return nil end
        local text = cleanText(value.text, 1000)
        return text and { type = value.type, kind = value.kind, text = text } or nil
    end
    if value.type == 'identity_document_shown' then
        local event = { type = value.type }
        for _, key in ipairs({ 'full_name', 'sex', 'ssn', 'issued_at', 'last_name' }) do
            event[key] = cleanText(value[key], 128)
            if not event[key] then return nil end
        end
        return event
    end
    if value.type == 'item_dropped' or value.type == 'item_picked_up' then
        if type(value.item_name) ~= 'string' or #value.item_name > 100
            or not value.item_name:match('^[%w_.-]+$')
            or type(value.quantity) ~= 'number' or value.quantity <= 0
            or value.quantity % 1 ~= 0 then return nil end
        return { type = value.type, item_name = value.item_name, quantity = value.quantity }
    end
    return nil
end

function HumalikeReportPlayerEvent(playerId, rawEvent)
    playerId = tonumber(playerId)
    if not playerId or playerId <= 0 or playerId % 1 ~= 0
        or not HumalikePlayer.IsCharacterLoaded(playerId) then return false end
    local event = validatedEvent(rawEvent)
    if not event then return false end
    HumalikePostPlayerEvent(playerId, event)
    return true
end

exports('ReportPlayerEvent', function(playerId, event)
    return HumalikeReportPlayerEvent(playerId, event)
end)

local handsUpStates = {}
for _, playerId in ipairs(GetPlayers()) do
    playerId = tonumber(playerId)
    handsUpStates[playerId] = Player(playerId).state.HandsUp == true
end

AddEventHandler('playerJoining', function()
    handsUpStates[source] = false
end)

AddStateBagChangeHandler('HandsUp', nil, function(bagName, _, value)
    local playerId = GetPlayerFromStateBagName(bagName)
    if not playerId or playerId <= 0 then return end
    local raised = value == true
    local previous = handsUpStates[playerId]
    handsUpStates[playerId] = raised
    if previous == nil or previous == raised then return end
    HumalikeReportPlayerEvent(playerId, {
        type = raised and 'hands_raised' or 'hands_lowered',
    })
end)

AddEventHandler('playerDropped', function()
    handsUpStates[source] = nil
end)
