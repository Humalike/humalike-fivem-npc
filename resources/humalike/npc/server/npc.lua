
NpcRegistry = {} -- npc_id (string) -> NpcRosterEntry-shaped table

HumalikeStatus = {
    lastRosterSyncAt = nil,
    lastRosterSyncOk = false,
    lastRosterError = nil,
}

local function visuallyEqual(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z
        and a.heading == b.heading and a.model == b.model
end

local function runtimeEqual(a, b)
    return a.voice_muted == b.voice_muted and a.language == b.language
end

local syncInFlight = false
local syncQueued = false
local queuedBindingRepair = false
local queuedCallbacks = {}
function SyncNpcRoster(onDone, repairBindings)
    if syncInFlight then
        syncQueued = true
        queuedBindingRepair = queuedBindingRepair or repairBindings == true
        if onDone then queuedCallbacks[#queuedCallbacks + 1] = onDone end
        return
    end
    syncInFlight = true

    local function finish(ok)
        syncInFlight = false
        if onDone then onDone(ok) end
        if not syncQueued then return end

        local nextRepair = queuedBindingRepair
        local callbacks = queuedCallbacks
        syncQueued = false
        queuedBindingRepair = false
        queuedCallbacks = {}
        SyncNpcRoster(function(nextOk)
            for _, callback in ipairs(callbacks) do callback(nextOk) end
        end, nextRepair)
    end

    HumalikeHttp.PostAction('get_npc_roster', {}, function(ok, status, body)
        HumalikeStatus.lastRosterSyncAt = os.time()
        HumalikeStatus.lastRosterSyncOk = ok
        HumalikeStatus.lastRosterError = ok and nil or ('HTTP ' .. tostring(status))

        if not ok or not body or not body.npcs then
            print(('[humalike-npc] get_npc_roster failed (HTTP %s) -- not touching spawned NPCs')
                :format(tostring(status)))
            finish(false)
            return
        end

        local incoming = {}
        for _, entry in ipairs(body.npcs) do
            incoming[entry.npc_id] = entry
        end
        HumalikeDebug('roster sync: fetched %d npc(s) from svc-npc', #body.npcs)
        for npcId, existing in pairs(NpcRegistry) do
            if not incoming[npcId] then
                if ResetNpcWorldState then ResetNpcWorldState(npcId) end
                ForgetNpcPose(npcId)
                RemovePersistentNpc(npcId)
                NpcRegistry[npcId] = nil
                TriggerClientEvent('humalike:npc:npcRemoved', -1, npcId)
                print(('[humalike-npc] roster sync: removed %s (%s)'):format(npcId, existing.name))
            end
        end
        for npcId, entry in pairs(incoming) do
            local existing = NpcRegistry[npcId]
            if not existing then
                EnsurePersistentNpc(entry)
                NpcRegistry[npcId] = entry
                TriggerClientEvent('humalike:npc:npcAdded', -1, entry)
                print(('[humalike-npc] roster sync: added %s (%s)'):format(npcId, entry.name))
            elseif not visuallyEqual(existing, entry) then
                if ResetNpcWorldState then ResetNpcWorldState(npcId) end
                RemovePersistentNpc(npcId)
                EnsurePersistentNpc(entry)
                NpcRegistry[npcId] = entry
                TriggerClientEvent('humalike:npc:npcRemoved', -1, npcId)
                TriggerClientEvent('humalike:npc:npcAdded', -1, entry)
                print(('[humalike-npc] roster sync: respawning %s (%s), position/model changed')
                    :format(npcId, entry.name))
            else
                entry.entity_id = existing.entity_id
                entry.network_id = existing.network_id
                entry.runtime_token = existing.runtime_token
                EnsurePersistentNpc(entry, repairBindings == true)
                NpcRegistry[npcId] = entry
                if not runtimeEqual(existing, entry) then
                    TriggerClientEvent('humalike:npc:npcAdded', -1, entry)
                end
            end
        end

        finish(true)
    end)
end
