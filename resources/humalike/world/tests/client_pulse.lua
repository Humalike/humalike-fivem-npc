local now = 0
local threads, natives, sent, printed = {}, {}, {}, {}
local function count(name) natives[name] = (natives[name] or 0) + 1 end

function CreateThread(callback) threads[#threads + 1] = callback end
function Wait(ms) coroutine.yield(ms) end
function GetGameTimer() return now end
function PlayerPedId() count('PlayerPedId') return 7 end
function GetEntityCoords(ped) count('GetEntityCoords') return { x = ped, y = 0.0, z = 0.0 } end
function GetEntityVelocity() count('GetEntityVelocity') return { x = 0.0, y = 0.0, z = 0.0 } end
function GetGameplayCamRot(order) count('GetGameplayCamRot') assert(order == 2) return { x = 0.0, y = 0.0, z = 0.0 } end
function GetGameplayCamCoord() count('GetGameplayCamCoord') return { x = 0.0, y = 0.0, z = 0.0 } end
function SendNuiMessage(json) sent[#sent + 1] = json end
local realPrint = print
function print(text) printed[#printed + 1] = text end

dofile('client/pulse.lua')
assert(#threads == 1, 'one thread for every periodic job')

local ran = {}
HumalikePulse.Every('slow', 200, function(at, due) ran[#ran + 1] = ('slow@%d/%d'):format(at, due) end, 80)
HumalikePulse.Every('fast', 100, function(at, due) ran[#ran + 1] = ('fast@%d/%d'):format(at, due) end, 20)
now = 1016
assert(HumalikePulse.Run(now) == 84, 'the first pulse runs every job and sleeps to the next grid point')
assert(ran[1] == 'fast@1016/1000' and ran[2] == 'slow@1016/1000', 'lower order first; due is the time it was scheduled for')
now = 1100
assert(HumalikePulse.Run(now) == 100 and #ran == 3 and ran[3] == 'fast@1100/1100')
now = 1217 -- a late frame
assert(HumalikePulse.Run(now) == 83 and #ran == 5, 'both are due at 1200')
assert(ran[4] == 'fast@1217/1200' and ran[5] == 'slow@1217/1200', 'a late wake still counts as its grid time')
now = 1299 -- a wake-up one millisecond early
assert(HumalikePulse.Run(now) == 101 and #ran == 6 and ran[6] == 'fast@1299/1300',
    'a job due within a millisecond runs now instead of costing a second wake-up')
now = 1400
HumalikePulse.Run(now)
assert(#ran == 8, 'and the next runs are back on the grid')
now = 2950 -- a long hitch: one run, not a burst of the missed ones
HumalikePulse.Run(now)
assert(#ran == 10)
now = 3000
assert(HumalikePulse.Run(now) == 100 and #ran == 12)

local cadence, cadenceRuns = 500, 0
HumalikePulse.Every('adaptive', 500, function() cadenceRuns = cadenceRuns + 1 return cadence end)
now = 3100
HumalikePulse.Run(now)
assert(cadenceRuns == 1)
now = 3400
HumalikePulse.Run(now)
assert(cadenceRuns == 1, 'next due at 3500')
cadence = 50
now = 3500
assert(HumalikePulse.Run(now) == 50 and cadenceRuns == 2, 'the returned interval sets the next run')
now = 3550
HumalikePulse.Run(now)
assert(cadenceRuns == 3)
cadence = 1000
now = 3600
HumalikePulse.Run(now)
now = 3900
HumalikePulse.Run(now)
assert(cadenceRuns == 4, 'and back to the slow cadence')

natives = {}
local seen = {}
HumalikePulse.Every('reader a', 100, function()
    seen.ped = HumalikePulse.Ped()
    seen.x = HumalikePulse.Coords().x
    HumalikePulse.Velocity()
    HumalikePulse.CamRot()
    HumalikePulse.CamCoord()
end)
HumalikePulse.Every('reader b', 100, function()
    assert(HumalikePulse.Ped() == 7 and HumalikePulse.Coords().x == 7)
    HumalikePulse.Velocity()
    HumalikePulse.CamRot()
    HumalikePulse.CamCoord()
end)
now = 4000
HumalikePulse.Run(now)
assert(seen.ped == 7 and seen.x == 7)
assert(natives.PlayerPedId == 1 and natives.GetEntityCoords == 1 and natives.GetEntityVelocity == 1
    and natives.GetGameplayCamRot == 1 and natives.GetGameplayCamCoord == 1, 'one read each per pulse')
now = 4100
HumalikePulse.Run(now)
assert(natives.PlayerPedId == 2 and natives.GetEntityCoords == 2, 'and a fresh one on the next pulse')
HumalikePulse.Ped()
HumalikePulse.Ped()
assert(natives.PlayerPedId == 4, 'outside a pulse every call asks the game')

sent = {}
local outbox = {}
HumalikePulse.Every('sender', 100, function()
    for _, message in ipairs(outbox) do HumalikePulse.Send(message) end
end)
outbox = { '{"type":"a"}', '{"type":"b","n":1}' }
now = 4200
HumalikePulse.Run(now)
assert(#sent == 1 and sent[1] == '{"type":"batch","messages":[{"type":"a"},{"type":"b","n":1}]}')
outbox = { '{"type":"c"}' }
now = 4300
HumalikePulse.Run(now)
assert(#sent == 2 and sent[2] == '{"type":"c"}')
outbox = { { type = 'not encoded' }, '{"type":"e"}' }
now = 4400
HumalikePulse.Run(now)
assert(#sent == 3 and sent[3] == '{"type":"e"}', 'only encoded messages are queued: one bad part cannot void a batch')
outbox = {}
now = 4500
HumalikePulse.Run(now)
assert(#sent == 3, 'nothing queued, nothing sent')
HumalikePulse.Send('{"type":"d"}')
assert(#sent == 4 and sent[4] == '{"type":"d"}', 'outside a pulse a message is sent at once')

local after = 0
HumalikePulse.Every('broken', 100, function() error('boom') end, 10)
HumalikePulse.Every('after', 100, function() after = after + 1 end, 90)
now = 4600
HumalikePulse.Run(now)
now = 4700
HumalikePulse.Run(now)
assert(after == 2, 'the jobs behind a failing one still run')
assert(#printed == 1 and printed[1]:find('periodic job broken failed', 1, true) and printed[1]:find('boom', 1, true),
    'one report, not one per run')
now = 4700 + 10000
HumalikePulse.Run(now)
assert(#printed == 2, 'and again ten seconds later')

local late = 0
HumalikePulse.Every('registrar', 100000, function()
    HumalikePulse.Every('late', 100, function() late = late + 1 end)
end)
now = 20000
assert(HumalikePulse.Run(now) == 0, 'a new job is due at once')
now = 20016
HumalikePulse.Run(now)
assert(late == 1)

local zero = 0
HumalikePulse.Every('zero', 0, function() zero = zero + 1 return 0 end)
now = 21000
assert(HumalikePulse.Run(now) <= 2 and zero == 1)
now = 21002
HumalikePulse.Run(now)
assert(zero == 2)

local scopes, depth = {}, 0
local profileJobs, recording, recordingChecks = false, true, 0
function GetConvarInt(name, default)
    assert(name == 'humalike_profile_jobs')
    return profileJobs and 1 or default
end
function ProfilerIsRecording() recordingChecks = recordingChecks + 1 return recording end
function ProfilerEnterScope(name) scopes[#scopes + 1] = name depth = depth + 1 end
function ProfilerExitScope() depth = depth - 1 end
now = 22000
HumalikePulse.Run(now)
assert(#scopes == 0 and recordingChecks == 0, 'by default a recording sees the one thread, and nobody asks about it')
profileJobs = true
now = 23000
HumalikePulse.Run(now)
assert(depth == 0 and #scopes > 3)
local named = {}
for _, name in ipairs(scopes) do named[name] = true end
assert(named['humalike pulse: fast'] and named['humalike pulse: broken'], 'even one that fails closes its scope')
now = 23100
HumalikePulse.Run(now)
assert(recordingChecks == 1, 'the question is asked once a second, not once a pulse')
recording = false
scopes = {}
now = 24100
HumalikePulse.Run(now)
assert(#scopes == 0, 'and nothing is paid for without a recording')
recording = 1 -- some builds answer 1 instead of true
now = 25100
HumalikePulse.Run(now)
assert(#scopes > 3, 'a recording is a recording however the native says so')
recording = 0
scopes = {}
now = 26100
HumalikePulse.Run(now)
assert(#scopes == 0)

local fastRuns = #ran
now = 500
HumalikePulse.Run(now)
assert(#ran > fastRuns, 'the jobs run again at once')

local pulse = coroutine.create(threads[1])
now = 600
local _, waited = coroutine.resume(pulse)
assert(waited <= 2, 'the job with no interval is due on the next frame')
print = realPrint

threads = {}
dofile('client/pulse.lua')
local edge, label, edgeBeats = {}, {}, {}
local sending = true
HumalikePulse.Every('label', 50, function(at) label[#label + 1] = at end, 60)
HumalikePulse.Every('edge', 200, function(at)
    edge[#edge + 1] = at
    edgeBeats[#edgeBeats + 1] = HumalikePulse.Beat(1000)
    if sending then HumalikePulse.Anchor() end
end, 80)
math.randomseed(7)
local wakeAt = 0
now = 100000
local stop = now + 60000
local pulses, seconds = 0, 0
local lastBeat
while now < stop do
    now = now + math.random(14, 19)
    if now >= wakeAt then
        pulses = pulses + 1
        wakeAt = now + HumalikePulse.Run(now)
        local beat = HumalikePulse.Beat(1000)
        if beat ~= lastBeat then lastBeat, seconds = beat, seconds + 1 end
    end
end
local shortest, longest = math.huge, 0
for index = 2, #edge do
    local gap = edge[index] - edge[index - 1]
    shortest, longest = math.min(shortest, gap), math.max(longest, gap)
end
assert(shortest >= 200, ('an anchoring job is never run less than its interval after its last run (shortest %d)'):format(shortest))
assert(longest <= 240, ('nor much later than a frame after it (longest %d)'):format(longest))
assert(#edge >= 270, ('about five runs a second (%d in a minute)'):format(#edge))
assert(#label >= 4 * #edge - 4 and #label <= 4 * #edge + 4,
    ('the 50 ms job keeps four runs per 200 ms run (%d and %d)'):format(#label, #edge))
local together = 0
do
    local at = {}
    for _, time in ipairs(label) do at[time] = true end
    for _, time in ipairs(edge) do if at[time] then together = together + 1 end end
end
assert(together == #edge, 'every 200 ms run shares its pulse with a 50 ms run')
assert(pulses <= #label + 2, ('and no pulse is spent between grid points (%d pulses, %d label runs)'):format(pulses, #label))
for index = 2, #edgeBeats do
    assert(edgeBeats[index] >= edgeBeats[index - 1], 'beats never go backwards')
end
assert(seconds >= 55 and seconds <= 61,
    ('a beat is about a second: the anchor stretches it by the frames that came late (%d in a minute)'):format(seconds))

sending = false
edge = {}
stop = now + 20000
while now < stop do
    now = now + math.random(14, 19)
    if now >= wakeAt then wakeAt = now + HumalikePulse.Run(now) end
end
shortest = math.huge
for index = 2, #edge do shortest = math.min(shortest, edge[index] - edge[index - 1]) end
assert(shortest < 200, 'which is why a sender whose receiver keeps one message per interval anchors')

print = function(text) printed[#printed + 1] = text end
local frameRuns, wanted = 0, 3
HumalikePulse.EveryFrame('frames', function()
    frameRuns = frameRuns + 1
    return frameRuns < wanted
end)
HumalikePulse.EveryFrame('broken frame', function() error('frame boom') end)
assert(#threads == 1, 'no frame thread until somebody asks for frames')
HumalikePulse.Frames()
HumalikePulse.Frames()
assert(#threads == 2, 'one frame thread, however often it is asked for')
local frame = coroutine.create(threads[2])
_, waited = coroutine.resume(frame)
assert(waited == 0 and frameRuns == 1)
coroutine.resume(frame)
coroutine.resume(frame)
assert(frameRuns == 3 and coroutine.status(frame) == 'dead', 'the thread ends when no job needs a frame')
assert(printed[#printed]:find('periodic job broken frame failed', 1, true), 'a failing frame job is reported, the others run')
wanted = 5
HumalikePulse.Frames()
assert(#threads == 3, 'and is started again on demand')
realPrint('client_pulse: ok')
