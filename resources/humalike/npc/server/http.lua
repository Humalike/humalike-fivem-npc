
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
local DEBUG_BODY_BYTES = 8 * 1024

function HumalikeHttp.PostAction(name, payload, callback)
    local requestBody = encodeBody(payload)
    HumalikeDebug('-> POST %s %s', name,
        #requestBody > DEBUG_BODY_BYTES and ('(%d bytes)'):format(#requestBody) or requestBody)
    HumaLike.PostEdgeAction(name, payload or {}, function(ok, status, decoded)
        HumalikeDebug('<- %s %s status=%s', name, ok and 'ok' or 'FAILED', status)
        if callback then callback(ok, status, decoded) end
    end)
end
