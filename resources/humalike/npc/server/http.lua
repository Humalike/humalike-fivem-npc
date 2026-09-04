
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
--- Bodies that are megabytes of game data files; the debug line shows a count.
local QUIET_ACTIONS = { upload_population_files = true }

function HumalikeHttp.PostAction(name, payload, callback)
    if QUIET_ACTIONS[name] then
        HumalikeDebug('-> POST %s (%d files)', name,
            type(payload) == 'table' and type(payload.files) == 'table' and #payload.files or 0)
    else
        HumalikeDebug('-> POST %s %s', name, encodeBody(payload))
    end
    HumaLike.PostEdgeAction(name, payload or {}, function(ok, status, decoded)
        HumalikeDebug('<- %s %s status=%s', name, ok and 'ok' or 'FAILED', status)
        if callback then callback(ok, status, decoded) end
    end)
end
