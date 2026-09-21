local handlers, bagHandlers, threads = {}, {}, {}
local started = { ['pma-voice'] = true, saltychat = true, ['yaca-voice'] = true }
local inCall = false
local callChannel = 0
function AddEventHandler(name, fn)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], fn)
end
local function fire(name, ...)
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
function AddStateBagChangeHandler(key, _, fn) bagHandlers[key] = fn end
function GetPlayerFromStateBagName(bag) return bag == 'player:1' and 1 or 2 end
function PlayerId() return 1 end
function GetResourceState(name) return started[name] and 'started' or 'stopped' end
function GetCurrentResourceName() return 'humalike' end
function GetInvokingResource() return nil end
function CreateThread(fn) threads[#threads + 1] = fn end
function Wait() error('stop') end
function exports() end
LocalPlayer = { state = setmetatable({}, { __index = function(_, key)
    if key == 'callChannel' then return callChannel end
end }) }
exports = setmetatable({ ['yaca-voice'] = { isInCall = function() return inCall end } },
    { __call = function() end })

dofile('client/ptt.lua')
dofile('client/busy.lua')
dofile('../integration/providers/pma_voice/client.lua')
dofile('../integration/providers/saltychat/client.lua')
dofile('../integration/providers/yaca/client.lua')

-- pma-voice
fire('pma-voice:radioActive', true)
assert(HumalikeVoiceBusy.Has(':radio'))
fire('pma-voice:radioActive', false)
assert(not HumalikeVoiceBusy.Active())
bagHandlers.callChannel('player:2', nil, 5)
assert(not HumalikeVoiceBusy.Active(), 'another player on the phone is not us')
bagHandlers.callChannel('player:1', nil, 5)
assert(HumalikeVoiceBusy.Has(':call'))
bagHandlers.callChannel('player:1', nil, 0)
assert(not HumalikeVoiceBusy.Active())
fire('pma-voice:radioActive', true)
fire('onClientResourceStop', 'pma-voice')
assert(not HumalikeVoiceBusy.Active(), 'a stopped pma-voice clears its reasons')
fire('pma-voice:radioActive', true)
assert(not HumalikeVoiceBusy.Active(), 'events from a stopped pma-voice are ignored')
callChannel = 3
fire('onClientResourceStart', 'pma-voice')
assert(HumalikeVoiceBusy.Has(':call'), 'a restart re-reads the current call')
callChannel = 0
bagHandlers.callChannel('player:1', nil, 0)

-- saltychat: transmit on either radio counts, receiving does not
fire('SaltyChat_RadioTrafficStateChanged', true, false, true, false)
assert(not HumalikeVoiceBusy.Active())
fire('SaltyChat_RadioTrafficStateChanged', false, false, false, true)
assert(HumalikeVoiceBusy.Has('saltychat:radio'))
fire('SaltyChat_RadioTrafficStateChanged', false, false, false, false)
assert(not HumalikeVoiceBusy.Active())
fire('SaltyChat_RadioTrafficStateChanged', false, true, false, false)
fire('onClientResourceStop', 'saltychat')
assert(not HumalikeVoiceBusy.Active())

-- yaca
fire('yaca:external:isRadioTalking', true, 1)
assert(HumalikeVoiceBusy.Has('yaca:radio'))
fire('yaca:external:isRadioTalking', false, 1)
assert(not HumalikeVoiceBusy.Active())
inCall = true
local ok = pcall(threads[#threads])
assert(not ok, 'the poll thread waits after one pass')
assert(HumalikeVoiceBusy.Has('yaca:call'))
inCall = false
pcall(threads[#threads])
assert(not HumalikeVoiceBusy.Active())
started['yaca-voice'] = nil
fire('yaca:external:isRadioTalking', true, 1)
assert(not HumalikeVoiceBusy.Active(), 'events from a stopped yaca are ignored')
print('busy_providers: ok')
