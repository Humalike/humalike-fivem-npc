--[[
    Shared-microphone (audio hub) adapter bridge.

    Some servers run a resource that owns the only microphone capture on the
    client and relays the live track to other NUI frames over a loopback
    RTCPeerConnection. An integration resource can register an adapter here so
    the voice NUI attaches to that shared capture instead of opening its own
    getUserMedia. Without a registered adapter every attach is answered with
    available = false and the NUI opens the device itself, which is the
    behavior servers without a hub already have.

    Only WebRTC negotiation blobs cross this bridge; audio never does.
]]

HumalikeVoiceAudioHub = {}
HumalikeAudioHubAdapters = HumalikeAudioHubAdapters or {}

local API_VERSION = 1
local selectedName = nil
local resolution = { state = 'unresolved' }
local sessions = {}

local function setting()
    return tostring((Config.Integrations or {}).audiohub or 'auto'):lower()
end

local function callable(value)
    return type(value) == 'function' or type(value) == 'table'
end

local function validName(value)
    return type(value) == 'string' and value:match('^[%w_.-]+$') ~= nil
        and value == value:lower() and value ~= 'none' and #value <= 64
end

local function validSessionId(value)
    return type(value) == 'string' and value:match('^[%w_.:-]+$') ~= nil
        and #value <= 64
end

local function available(adapter)
    if adapter.Available == nil then return true end
    local ok, result = pcall(adapter.Available)
    return ok and result == true
end

local function reportFailure(adapter, method, message)
    local now = GetGameTimer()
    local failure = adapter.failure or { count = 0, suppressed = 0 }
    failure.count = failure.count + 1
    failure.method = method
    failure.message = tostring(message)
    failure.at = now
    if not failure.reportedAt or now - failure.reportedAt >= 10000 then
        local suffix = failure.suppressed > 0
            and (' (%d suppressed)'):format(failure.suppressed) or ''
        print(('[humalike] audio hub adapter %s.%s failed: %s%s'):format(
            adapter.name, method, failure.message, suffix))
        failure.reportedAt = now
        failure.suppressed = 0
    else
        failure.suppressed = failure.suppressed + 1
    end
    adapter.failure = failure
    if selectedName == adapter.name then
        resolution.state = 'degraded'
        resolution.reason = ('%s callback failed'):format(method)
    end
end

local function call(adapter, method, ...)
    if not adapter or not callable(adapter[method]) then return false, nil end
    local result = table.pack(pcall(adapter[method], ...))
    if not result[1] then
        reportFailure(adapter, method, result[2])
        return false, nil
    end
    adapter.failure = nil
    if selectedName == adapter.name then
        resolution.state = 'selected'
        resolution.reason = nil
    end
    return true, table.unpack(result, 2, result.n)
end

local function resolve()
    local forced = setting()
    local eligible, highestPriority = {}, nil
    for name, adapter in pairs(HumalikeAudioHubAdapters) do
        adapter.name = name
        local priority = tonumber(adapter.priority) or 0
        if (forced == 'auto' or forced == name) and available(adapter) then
            if forced ~= 'auto' then
                eligible = { adapter }
                break
            elseif highestPriority == nil or priority > highestPriority then
                highestPriority = priority
                eligible = { adapter }
            elseif priority == highestPriority then
                eligible[#eligible + 1] = adapter
            end
        end
    end
    local selected
    if #eligible == 1 then
        selected = eligible[1]
        resolution = { state = selected.failure and 'degraded' or 'selected' }
    elseif #eligible > 1 then
        resolution = { state = 'ambiguous',
            reason = 'multiple adapters share the highest priority' }
    elseif forced == 'none' then
        resolution = { state = 'disabled' }
    else
        resolution = { state = 'unavailable', reason = 'no available adapter' }
    end
    selectedName = selected and selected.name or nil
    return selected
end

local function sessionAdapter(session)
    local adapter = HumalikeAudioHubAdapters[session.adapter]
    if adapter and adapter.ownerResource == session.owner then return adapter end
    return nil
end

---Drop every session served by one adapter and tell the NUI page why, so it
---can abandon the dead peer connection and fall back to its own capture.
local function failSessions(adapterName, reason)
    for id, session in pairs(sessions) do
        if session.adapter == adapterName then
            sessions[id] = nil
            SendNUIMessage({ type = 'audiohub:state', id = id,
                state = { capturing = false, error = reason, consumers = 0 } })
        end
    end
end

---Detach every open session without notifying the page. Used when the page
---itself went away (NUI reboot) or this resource is stopping.
function HumalikeVoiceAudioHub.Reset()
    for id, session in pairs(sessions) do
        sessions[id] = nil
        local adapter = sessionAdapter(session)
        if adapter then call(adapter, 'Detach', id) end
    end
end

--[[ NUI page -> adapter ]]

RegisterNUICallback('audiohubAttach', function(data, callback)
    if type(data) ~= 'table' or not validSessionId(data.id) then
        callback({ ok = false, available = false })
        return
    end
    local adapter = resolve()
    if not adapter then
        callback({ ok = true, available = false })
        return
    end
    sessions[data.id] = { adapter = adapter.name, owner = adapter.ownerResource }
    local ok, accepted = call(adapter, 'Attach', data.id,
        { track = data.track == true, level = data.level == true })
    if not ok or accepted == false then
        sessions[data.id] = nil
        callback({ ok = true, available = false })
        return
    end
    callback({ ok = true, available = true })
end)

RegisterNUICallback('audiohubDetach', function(data, callback)
    callback({ ok = true })
    if type(data) ~= 'table' or not validSessionId(data.id) then return end
    local session = sessions[data.id]
    if not session then return end
    sessions[data.id] = nil
    local adapter = sessionAdapter(session)
    if adapter then call(adapter, 'Detach', data.id) end
end)

RegisterNUICallback('audiohubSignal', function(data, callback)
    callback({ ok = true })
    if type(data) ~= 'table' or not validSessionId(data.id)
        or data.payload == nil then return end
    local session = sessions[data.id]
    if not session then return end
    local adapter = sessionAdapter(session)
    if adapter then call(adapter, 'Signal', data.id, data.payload) end
end)

--[[ Adapter -> NUI page ]]

exports('AudioHubDeliver', function(id, action, data)
    local owner = GetInvokingResource()
    if not owner or not validSessionId(id) then return false end
    local session = sessions[id]
    if not session or session.owner ~= owner then return false end
    if action == 'signal' then
        if data == nil then return false end
        SendNUIMessage({ type = 'audiohub:signal', id = id, payload = data })
    elseif action == 'state' then
        if type(data) ~= 'table' then return false end
        SendNUIMessage({ type = 'audiohub:state', id = id, state = data })
    else
        return false
    end
    return true
end)

--[[ Registration ]]

exports('RegisterAudioHub', function(descriptor)
    local owner = GetInvokingResource()
    if not owner or type(descriptor) ~= 'table'
        or descriptor.apiVersion ~= API_VERSION
        or not validName(descriptor.name)
        or type(descriptor.priority) ~= 'number'
        or descriptor.priority ~= descriptor.priority
        or math.abs(descriptor.priority) > 100000
        or not callable(descriptor.Attach) or not callable(descriptor.Detach)
        or not callable(descriptor.Signal)
        or descriptor.Available ~= nil and not callable(descriptor.Available) then
        return false, 'invalid audio hub adapter'
    end
    local existing = HumalikeAudioHubAdapters[descriptor.name]
    if existing and existing.ownerResource ~= owner then
        return false, 'adapter name already registered'
    end
    local adapter = {}
    for key, value in pairs(descriptor) do adapter[key] = value end
    adapter.ownerResource = owner
    adapter.priority = descriptor.priority
    HumalikeAudioHubAdapters[adapter.name] = adapter
    resolve()
    return true
end)

exports('UnregisterAudioHub', function(name)
    local owner = GetInvokingResource()
    if not owner or not validName(name) then return false, 'invalid adapter' end
    local adapter = HumalikeAudioHubAdapters[name]
    if not adapter then return true end
    if adapter.ownerResource ~= owner then
        return false, 'adapter owned by another resource'
    end
    HumalikeAudioHubAdapters[name] = nil
    failSessions(name, 'hub-stopped')
    resolve()
    return true
end)

exports('GetAudioHubStatus', function()
    resolve()
    local selected = selectedName and HumalikeAudioHubAdapters[selectedName] or nil
    local count = 0
    for _ in pairs(sessions) do count = count + 1 end
    return {
        apiVersion = API_VERSION,
        setting = setting(),
        state = resolution.state,
        reason = resolution.reason,
        selected = selected and {
            name = selected.name,
            ownerResource = selected.ownerResource,
            priority = selected.priority,
        } or false,
        sessions = count,
    }
end)

--[[ Lifecycle ]]

AddEventHandler('onClientResourceStart', function()
    resolve()
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        HumalikeVoiceAudioHub.Reset()
        return
    end
    for name, adapter in pairs(HumalikeAudioHubAdapters) do
        if adapter.ownerResource == resourceName then
            HumalikeAudioHubAdapters[name] = nil
            failSessions(name, 'hub-stopped')
        end
    end
    resolve()
end)
