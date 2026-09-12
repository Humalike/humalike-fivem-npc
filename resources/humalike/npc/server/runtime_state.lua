HumalikeNpcRuntimeState = HumalikeNpcRuntimeState or {}

local revision = 0
local syncInFlight, syncQueued, retryAttempt = false, false, 0
local retryScheduled, retryGeneration = false, 0

local function snapshot()
    local credentials = HumaLike.RuntimeCredentials()
    return {
        boot_id = credentials and credentials.bootId or '',
        revision = revision,
        controls = HumalikeNpcRuntimeControl and HumalikeNpcRuntimeControl.EdgeControls() or {},
        suppressed_static_npc_ids = HumalikeNpcEntityOwnership
            and HumalikeNpcEntityOwnership.SuppressedStaticNpcIds() or {},
    }
end

local function cancelRetry()
    retryGeneration = retryGeneration + 1
    retryScheduled = false
end

local syncState
local function scheduleRetry()
    if retryScheduled then return end
    retryScheduled = true
    retryGeneration = retryGeneration + 1
    local generation = retryGeneration
    SetTimeout(500 * (2 ^ (retryAttempt - 1)), function()
        if not retryScheduled or retryGeneration ~= generation then return end
        retryScheduled = false
        syncState()
    end)
end

syncState = function()
    if syncInFlight or not HumaLike.RuntimeCredentials() then
        syncQueued = true
        return
    end
    cancelRetry()
    syncInFlight, syncQueued = true, false
    local sentRevision = revision
    local sentAssignment = HumaLike.EdgeAssignmentKey()
    HumalikeHttp.PostAction('sync_npc_runtime_state', snapshot(), function(ok)
        if not HumaLike.IsCurrentEdgeAssignment(sentAssignment) then
            ok = false
            syncQueued = true
        end
        syncInFlight = false
        if ok then
            retryAttempt = 0
            cancelRetry()
        else
            retryAttempt = math.min(retryAttempt + 1, 6)
        end
        if syncQueued or revision ~= sentRevision then
            syncState()
        elseif not ok then
            scheduleRetry()
        end
    end)
end

function HumalikeNpcRuntimeState.Publish()
    revision = revision + 1
    syncState()
end

function HumalikeNpcRuntimeState.Sync()
    syncState()
end

AddEventHandler('humalike:core:ready', syncState)
AddEventHandler('humalike:runtime:edgeChanged', syncState)
AddEventHandler('humalike:runtime:refreshed', function(runtime)
    if not runtime or runtime.edgeChanged ~= true then syncState() end
end)
