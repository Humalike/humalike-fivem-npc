
function HumalikeNpcReportCapabilities()
    local population = HumalikeNpcPopulation
    local features = population and population.Features() or nil
    if population then population.CapabilitiesPosted() end
    local actions, observations = HumalikeActions.Declarations()
    HumalikeHttp.PostAction('report_capabilities', {
        supported_actions = GetSupportedActions(),
        features = features,
        actions = actions,
        observations = observations,
    }, function(ok, status, body)
        if population then population.CapabilitiesReported(features, ok) end
        if ok then return end
        print(('[humalike-npc] report_capabilities failed (%s)'):format(
            HumalikeHttp.DescribeFailure(status, body)))
    end)
end
local reportCapabilities = HumalikeNpcReportCapabilities

local pendingReadyGeneration

local function rosterSynced(ok)
    if not ok or not pendingReadyGeneration then return end
    local generation = pendingReadyGeneration
    pendingReadyGeneration = nil
    TriggerEvent('humalike:npc:ready', { apiVersion = 1, generation = generation })
end

AddEventHandler('humalike:core:ready', function(runtime)
    pendingReadyGeneration = runtime and runtime.generation or 0
    SyncNpcRoster(rosterSynced, true)
    reportCapabilities()
end)

local function replayEdgeState()
    SyncNpcRoster(nil, true)
    reportCapabilities()
end

AddEventHandler('humalike:runtime:edgeChanged', replayEdgeState)
AddEventHandler('humalike:runtime:refreshed', function(runtime)
    if not runtime or runtime.edgeChanged ~= true then replayEdgeState() end
end)

AddEventHandler('humalike:providers:changed', function(domain)
    if (domain == 'inventory' or domain == 'actions')
        and HumaLike.RuntimeCredentials() then reportCapabilities() end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    CreateThread(function()
        while true do
            Wait(Config.RosterSyncIntervalMs)
            SyncNpcRoster(rosterSynced)
        end
    end)
end)
RegisterNetEvent('humalike:npc:requestRoster')
AddEventHandler('humalike:npc:requestRoster', function()
    local source = source
    local snapshot = {}
    for _, entry in pairs(NpcRegistry) do
        if entry.entity_id and DoesEntityExist(entry.entity_id) then
            snapshot[#snapshot + 1] = entry
        end
    end
    TriggerClientEvent('humalike:npc:rosterSnapshot', source, snapshot)
end)

local function populationSummary()
    local rows = HumalikeNpcPopulation and HumalikeNpcPopulation.Bodies() or {}
    if #rows == 0 then return 'none' end
    local parts = {}
    for _, row in ipairs(rows) do
        parts[#parts + 1] = ('%s:%s%s'):format(row.body_id, row.status,
            row.kept and ('(' .. row.kept .. ')') or '')
    end
    return ('%d [%s]'):format(#rows, table.concat(parts, ' '))
end

RegisterCommand('humalikenpc:status', function(source)
    local count = 0
    for _ in pairs(NpcRegistry) do count = count + 1 end
    local lines = {
        ('player provider: %s'):format(HumalikePlayer.Name() or 'none'),
        ('npcs in roster: %d'):format(count),
        ('population: enabled=%s bodies=%s'):format(
            tostring(HumalikeNpcPopulation and HumalikeNpcPopulation.Enabled() or false),
            populationSummary()),
        ('last roster sync: %s (%s)'):format(
            HumalikeStatus.lastRosterSyncAt and os.date('%Y-%m-%d %H:%M:%S', HumalikeStatus.lastRosterSyncAt) or 'never',
            HumalikeStatus.lastRosterSyncOk and 'ok' or ('failed: ' .. tostring(HumalikeStatus.lastRosterError))
        ),
    }
    for _, line in ipairs(lines) do
        print('[humalike-npc] ' .. line)
        if source ~= 0 then
            TriggerClientEvent('chat:addMessage', source, { args = { 'humalike-npc', line } })
        end
    end
end, true)

RegisterCommand('humalikenpc:reload', function(source)
    SyncNpcRoster(function(ok)
        local msg = ok and 'roster sync complete' or 'roster sync failed, see server console'
        print('[humalike-npc] ' .. msg)
        if source ~= 0 then
            TriggerClientEvent('chat:addMessage', source, { args = { 'humalike-npc', msg } })
        end
    end, true)
end, true)
CreateThread(function()
    local wounded = Config.Wounded or {}
    print(('[humalike-npc] config: wounded=%s window=%sms death=%s%% medics=[%s] '
        .. 'police=[%s] duty=%s | pose abandon=%sms/%sm')
        :format(
            tostring(wounded.Enabled), tostring(wounded.DurationMs),
            tostring(wounded.DeathChancePercent),
            table.concat(wounded.MedicJobs or {}, ','),
            table.concat(wounded.PoliceJobs or {}, ','),
            tostring(wounded.RequireDuty),
            tostring(Config.PoseAbandonMs), tostring(Config.PoseAbandonRadius)))
end)
