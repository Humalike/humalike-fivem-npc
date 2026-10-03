-- One clock for the client's periodic work. Each poll used to own a thread:
-- a wake-up costs a few microseconds, so did every copy of PlayerPedId and
-- GetEntityCoords the polls read on their own, and every NUI message is a
-- cross-process call. Jobs registered here run on one thread and one grid (a
-- 100 ms job runs at ...100, 200, 300 of the pulse's clock), so jobs that are
-- due together wake the resource once, read the player once, and their NUI
-- messages leave as one.
HumalikePulse = { now = 0 }

local MAX_SLEEP_MS = 1000
local ERROR_REPORT_GAP_MS = 10000
local PROFILER_CHECK_MS = 1000
-- A wake-up can come a millisecond early; a job due within this is due.
local EARLY_MS = 1

local jobs, pending = {}, {}
local inPulse = false
local serial = 0 -- one per pulse; a shared read is valid for the pulse it was made in
local profiling, profilingAt = false, -PROFILER_CHECK_MS
-- The grid counts from `epoch`. Anchor() moves it to the pulse it was called
-- in, so the next run of every job is a whole interval after this one.
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

-- `run(now, due)` is called every `interval` ms. `now` is the game timer;
-- `due` is the time the run was scheduled for (`now` less however late the
-- frame came), so two runs of a job are never less than its interval apart on
-- `due`: count "at least N ms since" on it, not on `now`. A number returned by
-- `run` is the interval until its next run. Lower `order` runs first within a
-- pulse. A job must never yield.
function HumalikePulse.Every(name, interval, run, order)
    interval = tonumber(interval) or MAX_SLEEP_MS
    if interval < 1 then interval = 1 end -- a convar may say 0
    local job = { name = name, scope = 'humalike pulse: ' .. name, interval = interval, every = interval,
        run = run, order = order or 50, nextAt = 0, ranIn = 0, reportedAt = nil }
    if inPulse then pending[#pending + 1] = job else insert(job) end
    return job
end

-- How many whole `period`s the pulse's clock has counted. Every job of a pulse
-- reads the same number, and jobs whose intervals divide the period see it
-- change on the same pulse: the way to do something once a period, together.
function HumalikePulse.Beat(period)
    return (HumalikePulse.now + EARLY_MS - epoch) // period
end

-- For a job that just sent something whose receiver wants the next one a whole
-- interval later (the edge keeps one frame per 200 ms tick, so a frame sent
-- 190 ms after a late one can replace it): the grid restarts at this pulse.
function HumalikePulse.Anchor()
    if inPulse then anchorBy = late end
end

-- The player's ped, position, velocity and camera: each is read from the game
-- at most once per pulse, however many jobs ask. Outside a pulse every call
-- reads the game.
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

-- `playerPed` is the ped the caller already holds, when it has one.
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

-- NUI messages, already encoded. Those posted during a pulse leave together
-- as `{"type":"batch","messages":[...]}`; the NUI host hands each part to the
-- page's listeners as if it had arrived alone. Outside a pulse a message is
-- sent at once.
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

-- A failing job is reported with its traceback, at most every ten seconds,
-- and the jobs behind it still run.
local traceback = debug and debug.traceback or function(message) return message end

local function report(job, now, failure)
    if job.reportedAt and now - job.reportedAt < ERROR_REPORT_GAP_MS then return end
    job.reportedAt = now
    print(('^1[humalike] periodic job %s failed: %s^7'):format(job.name, tostring(failure)))
end

-- A profiler recording shows this thread as one row. With
-- `setr humalike_profile_jobs 1` each job runs inside a profiler scope of its
-- own name while a recording runs (the scope natives are the ones the
-- scheduler wraps a thread in; they cost two natives per job run, so such a
-- recording reads a little above what a player pays). Asked once a second.
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

-- One pulse: every due job runs, then the queued NUI messages are sent.
-- Returns the milliseconds until the next job is due.
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
        -- The grid restarts here: a job that ran is next due a whole interval
        -- from now (even if that wake-up comes a millisecond early), the others
        -- keep their place on the grid.
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

-- Work the game needs on every frame (a density multiplier lasts one frame; a
-- shot is visible for one). `run()` returns true while it still needs the
-- next frame. The frame thread lives only while some job does; Frames() starts
-- it again.
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
            -- Nothing in Run is expected to raise; if it does, the pulse survives it.
            inPulse = false
            print(('^1[humalike] pulse failed: %s^7'):format(tostring(sleep)))
            sleep = 100
        end
        Wait(sleep)
    end
end)
