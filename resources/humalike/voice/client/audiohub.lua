-- Shared-microphone (audio hub) adapter bridge. Only WebRTC signalling crosses
-- it; audio never does. Protocol: INTEGRATIONS.md, "Client audio hub".

HumalikeVoiceAudioHub = {}
HumalikeAudioHubAdapters = HumalikeAudioHubAdapters or {}

local API_VERSION = 1
local POLL_MS = 2500

local sessions = {}
local serving = false

local registry = HumalikeProviderRegistry.new({
    domain = 'audiohub', label = 'audio hub adapter', noun = 'adapter',
    adapters = HumalikeAudioHubAdapters,
    extra = function()
        local count = 0
        for _ in pairs(sessions) do count = count + 1 end
        return (' sessions=%d'):format(count)
    end,
})

local function validSessionId(value)
    return type(value) == 'string' and value:match('^[%w_.:-]+$') ~= nil
        and #value <= 64
end

local function sessionAdapter(session)
    local adapter = HumalikeAudioHubAdapters[session.adapter]
    if adapter and adapter.ownerResource == session.owner then return adapter end
    return nil
end

---Forget a session; `detach` tells the adapter, `reason` tells the page.
local function drop(id, detach, reason)
    local session = sessions[id]
    if not session then return false end
    sessions[id] = nil
    local detached = true
    if detach then
        local adapter = sessionAdapter(session)
        detached = adapter ~= nil and registry.call(adapter, 'Detach', id)
    end
    if reason then
        SendNUIMessage({ type = 'audiohub:state', id = id,
            state = { capturing = false, error = reason } })
    end
    return detached
end

---Re-selects the adapter, fails sessions the selection no longer covers and
---tells the page when a hub becomes available again.
local function resolve()
    local selected = registry.resolve()
    for id, session in pairs(sessions) do
        if not selected or selected.name ~= session.adapter
            or selected.ownerResource ~= session.owner then
            drop(id, true, 'hub-unavailable')
        end
    end
    if selected and not serving then SendNUIMessage({ type = 'audiohub:available' }) end
    serving = selected ~= nil
    return selected
end

---Detach every open session without notifying the page: the page itself went
---away (NUI reboot) or this resource is stopping.
function HumalikeVoiceAudioHub.Reset()
    for id in pairs(sessions) do drop(id, true, nil) end
end

function HumalikeVoiceAudioHub.Poll()
    resolve()
end

-- NUI page -> adapter

RegisterNUICallback('audiohubAttach', function(data, callback)
    if type(data) ~= 'table' or not validSessionId(data.id) then
        callback({ ok = false, reason = 'invalid_session' })
        return
    end
    if sessions[data.id] then
        callback({ ok = false, reason = 'already_attached' })
        return
    end
    local adapter = resolve()
    if not adapter then
        local state = registry.resolution.state
        if state == 'disabled' or (next(HumalikeAudioHubAdapters) == nil
            and registry.setting() == 'auto') then
            callback({ ok = true, status = 'none' })
        else
            callback({ ok = true, status = 'unavailable', reason = state })
        end
        return
    end
    sessions[data.id] = { adapter = adapter.name, owner = adapter.ownerResource }
    local ok, accepted = registry.call(adapter, 'Attach', data.id)
    if not ok or accepted ~= true then
        sessions[data.id] = nil
        callback({ ok = true, status = 'unavailable',
            reason = ok and 'attach_refused' or 'attach_failed' })
        return
    end
    callback({ ok = true, status = 'attached' })
end)

RegisterNUICallback('audiohubDetach', function(data, callback)
    if type(data) ~= 'table' or not validSessionId(data.id) then
        callback({ ok = false, reason = 'invalid_session' })
    elseif not sessions[data.id] then
        callback({ ok = false, reason = 'unknown_session' })
    elseif drop(data.id, true, nil) then
        callback({ ok = true })
    else
        callback({ ok = false, reason = 'detach_failed' })
    end
end)

RegisterNUICallback('audiohubSignal', function(data, callback)
    if type(data) ~= 'table' or not validSessionId(data.id) or data.payload == nil then
        callback({ ok = false, reason = 'invalid_request' })
        return
    end
    local session = sessions[data.id]
    if not session then
        callback({ ok = false, reason = 'unknown_session' })
        return
    end
    local adapter = sessionAdapter(session)
    if adapter and registry.call(adapter, 'Signal', data.id, data.payload) then
        callback({ ok = true })
        return
    end
    drop(data.id, true, nil)
    callback({ ok = false, reason = 'signal_failed' })
end)

-- Adapter -> NUI page

exports('AudioHubDeliver', function(id, action, data)
    local owner = GetInvokingResource()
    if not owner or not validSessionId(id) then return false, 'invalid_session' end
    local session = sessions[id]
    if not session or session.owner ~= owner then return false, 'unknown_session' end
    if action == 'signal' then
        if type(data) ~= 'table' then return false, 'invalid_payload' end
        SendNUIMessage({ type = 'audiohub:signal', id = id, payload = data })
    elseif action == 'state' then
        if type(data) ~= 'table' then return false, 'invalid_state' end
        SendNUIMessage({ type = 'audiohub:state', id = id, state = data })
    else
        return false, 'invalid_action'
    end
    return true
end)

-- Registration

exports('RegisterAudioHub', function(descriptor)
    local owner = GetInvokingResource()
    if not owner or type(descriptor) ~= 'table'
        or descriptor.apiVersion ~= API_VERSION
        or not registry.validDescriptor(descriptor, { 'Attach', 'Detach', 'Signal' }) then
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
    if not owner or not HumalikeProviderRegistry.validName(name) then
        return false, 'invalid adapter'
    end
    local adapter = HumalikeAudioHubAdapters[name]
    if not adapter then return true end
    if adapter.ownerResource ~= owner then
        return false, 'adapter owned by another resource'
    end
    for id, session in pairs(sessions) do
        if session.adapter == name then drop(id, true, 'hub-stopped') end
    end
    HumalikeAudioHubAdapters[name] = nil
    resolve()
    return true
end)

exports('GetAudioHubStatus', function()
    local status = registry.status()
    status.apiVersion = API_VERSION
    local count = 0
    for _ in pairs(sessions) do count = count + 1 end
    status.sessions = count
    return status
end)

-- Lifecycle

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
            for id, session in pairs(sessions) do
                if session.adapter == name then drop(id, false, 'hub-stopped') end
            end
        end
    end
    resolve()
end)

if type(CreateThread) == 'function' then
    CreateThread(function()
        while true do
            Wait(POLL_MS)
            resolve()
        end
    end)
end
