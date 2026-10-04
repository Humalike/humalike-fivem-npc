-- One thread and one grid for the client's periodic jobs.
HumalikePulse = { now = 0 }

local MAX_SLEEP_MS = 1000
local ERROR_REPORT_GAP_MS = 10000
local PROFILER_CHECK_MS = 1000
-- A wake-up can come a millisecond early; a job due within this is due.
local EARLY_MS = 1

local jobs, pending = {}, {}
local inPulse = false
local serial = 0 -- one per pulse
local profiling, profilingAt = false, -PROFILER_CHECK_MS
local epoch = 0
local late, anchorBy = 0, nil

local function insert(job)
    local at = #jobs + 1
    while at > 1 and jobs[at - 1].order > job.order do
        jobs[at] = jobs[at - 1]
        at = at - 1
    end
    jobs[at] = job
end

-- run(now, due): `due` is the scheduled time; count cadences on it, not on a late `now`.
-- A returned number is the next interval. A job must never yield.
function HumalikePulse.Every(name, interval, run, order)
    interval = tonumber(interval) or MAX_SLEEP_MS
    if interval < 1 then interval = 1 end -- a convar may say 0
    local job = { name = name, scope = 'humalike pulse: ' .. name, interval = interval, every = interval,
        run = run, order = order or 50, nextAt = 0, ranIn = 0, reportedAt = nil }
    if inPulse then pending[#pending + 1] = job else insert(job) end
    return job
end

-- Whole `period`s on the pulse's clock: the same number for every job of a pulse.
function HumalikePulse.Beat(period)
    return (HumalikePulse.now + EARLY_MS - epoch) // period
end

-- Restarts the grid at this pulse: the next run of every job is a whole interval away.
function HumalikePulse.Anchor()
    if inPulse then anchorBy = late end
end

-- Read from the game at most once per pulse.
local pedAt, ped = -1, 0
local coordsAt, coords = -1, nil
local velocityAt, velocity = -1, nil
local camRotAt, camRot = -1, nil
local camCoordAt, camCoord = -1, nil

function HumalikePulse.Ped()
    if inPulse and pedAt == serial then return ped end
    ped, pedAt = PlayerPedId() or 0, serial
    return ped
end

function HumalikePulse.Coords(playerPed)
    if inPulse and coordsAt == serial then return coords end
    coords, coordsAt = GetEntityCoords(playerPed or HumalikePulse.Ped()), serial
    return coords
end

function HumalikePulse.Velocity(playerPed)
    if inPulse and velocityAt == serial then return velocity end
    velocity, velocityAt = GetEntityVelocity(playerPed or HumalikePulse.Ped()), serial
    return velocity
end

function HumalikePulse.CamRot()
    if inPulse and camRotAt == serial then return camRot end
    camRot, camRotAt = GetGameplayCamRot(2), serial
    return camRot
end

function HumalikePulse.CamCoord()
    if inPulse and camCoordAt == serial then return camCoord end
    camCoord, camCoordAt = GetGameplayCamCoord(), serial
    return camCoord
end

-- Messages queued during a pulse leave as one {"type":"batch"} call.
local outbox, outboxCount = {}, 0

function HumalikePulse.Send(json)
    if type(json) ~= 'string' then return end
    if not inPulse then
        SendNuiMessage(json)
        return
    end
    outboxCount = outboxCount + 1
    outbox[outboxCount] = json
end

local function flush()
    if outboxCount == 0 then return end
    local count = outboxCount
    outboxCount = 0
    if count == 1 then
        SendNuiMessage(outbox[1])
    else
        SendNuiMessage('{"type":"batch","messages":[' .. table.concat(outbox, ',', 1, count) .. ']}')
    end
    for index = 1, count do outbox[index] = nil end
end

local traceback = debug and debug.traceback or function(message) return message end

local function report(job, now, failure)
    if job.reportedAt and now - job.reportedAt < ERROR_REPORT_GAP_MS then return end
    job.reportedAt = now
    print(('^1[humalike] periodic job %s failed: %s^7'):format(job.name, tostring(failure)))
end

-- With humalike_profile_jobs 1 a profiler recording shows each job under its own name.
local function profilerRecording(now)
    if now - profilingAt >= PROFILER_CHECK_MS or now < profilingAt then
        profilingAt = now
        local recording = GetConvarInt ~= nil and GetConvarInt('humalike_profile_jobs', 0) == 1
            and ProfilerIsRecording ~= nil and ProfilerIsRecording()
        -- The native answers false, and true or 1 depending on the build.
        profiling = recording == true or (type(recording) == 'number' and recording ~= 0)
    end
    return profiling
end

function HumalikePulse.Run(now)
    serial = serial + 1
    inPulse = true
    HumalikePulse.now = now
    anchorBy = nil
    local scoped = profilerRecording(now)
    local clock = now + EARLY_MS - epoch
    local soonest = now + MAX_SLEEP_MS
    for index = 1, #jobs do
        local job = jobs[index]
        -- A game timer that went backwards must not park a job for good.
        if job.nextAt - now > job.every + EARLY_MS then job.nextAt = 0 end
        if now + EARLY_MS >= job.nextAt then
            local interval = job.interval
            late = clock % job.every - EARLY_MS -- how far past its grid point this run is
            if scoped then ProfilerEnterScope(job.scope) end
            local ok, result = xpcall(job.run, traceback, now, now - late)
            if scoped then ProfilerExitScope() end
            if not ok then
                report(job, now, result)
            elseif type(result) == 'number' then
                interval = result
            end
            if interval < 1 then interval = 1 end
            job.every = interval
            job.ranIn = serial
            job.nextAt = now + EARLY_MS - clock % interval + interval
        end
        if job.nextAt < soonest then soonest = job.nextAt end
    end
    inPulse = false
    local shift = anchorBy and anchorBy + EARLY_MS or 0
    if shift > 0 then
        epoch = epoch + shift
        soonest = now + MAX_SLEEP_MS
        for index = 1, #jobs do
            local job = jobs[index]
            if job.ranIn == serial then
                job.nextAt = now + EARLY_MS - (now + EARLY_MS - epoch) % job.every + job.every
            elseif job.nextAt > 0 then
                job.nextAt = job.nextAt + shift
            end
            if job.nextAt < soonest then soonest = job.nextAt end
        end
    end
    if #pending > 0 then
        for index = 1, #pending do insert(pending[index]) end
        pending = {}
        soonest = now
    end
    flush()
    return math.max(0, soonest - now)
end

-- Per-frame jobs: run() returns true while it needs the next frame.
local frameJobs, frameThread = {}, false

function HumalikePulse.EveryFrame(name, run)
    frameJobs[#frameJobs + 1] = { name = name, run = run }
end

local function frames()
    while true do
        local busy = false
        for index = 1, #frameJobs do
            local job = frameJobs[index]
            local ok, result = xpcall(job.run, traceback)
            if not ok then
                report(job, GetGameTimer(), result)
            elseif result then
                busy = true
            end
        end
        if not busy then break end
        Wait(0)
    end
    frameThread = false
end

function HumalikePulse.Frames()
    if frameThread then return end
    frameThread = true
    CreateThread(frames)
end

CreateThread(function()
    while true do
        local ok, sleep = pcall(HumalikePulse.Run, GetGameTimer())
        if not ok then
            inPulse = false
            print(('^1[humalike] pulse failed: %s^7'):format(tostring(sleep)))
            sleep = 100
        end
        Wait(sleep)
    end
end)
