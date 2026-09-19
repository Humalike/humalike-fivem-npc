
HumalikeHttp = {}
local sourceEventSequence = 0

function HumalikeHttp.NextSourceEventId(playerId)
    sourceEventSequence = sourceEventSequence + 1
    return ('%d:%d:%d:%d'):format(
        playerId, os.time(), GetGameTimer(), sourceEventSequence
    )
end
local function encodeBody(payload)
    payload = payload or {}
    if next(payload) == nil then
        return '{}'
    end
    return json.encode(payload)
end
function HumalikeHttp.PostAction(name, payload, callback)
    local requestBody = encodeBody(payload)
    HumalikeDebug('-> POST %s %s', name, requestBody)
    HumaLike.PostEdgeAction(name, payload or {}, function(ok, status, decoded)
        HumalikeDebug('<- %s %s status=%s', name, ok and 'ok' or 'FAILED', status)
        if callback then callback(ok, status, decoded) end
    end)
end

function HumalikeHttp.DescribeFailure(status, body)
    local failure = type(body) == 'table' and type(body.error) == 'table' and body.error or {}
    local details = {}
    for _, detail in ipairs(type(failure.details) == 'table' and failure.details or {}) do
        if type(detail) == 'table' then
            details[#details + 1] = ('%s: %s'):format(tostring(detail.field), tostring(detail.message))
        end
    end
    return ('HTTP %s%s%s'):format(tostring(status),
        failure.code and ' ' .. tostring(failure.code) or '',
        #details > 0 and ': ' .. table.concat(details, '; ') or '')
end
