local handlers, exported = {}, {}
local invoking = 'other_resource'
function AddEventHandler(name, fn) handlers[name] = fn end
function GetCurrentResourceName() return 'humalike' end
function GetInvokingResource() return invoking end
function exports(name, fn) exported[name] = fn end

dofile('client/busy.lua')

local changes = {}
HumalikeVoiceBusy.Subscribe(function(active) changes[#changes + 1] = active end)
assert(not HumalikeVoiceBusy.Active())
assert(HumalikeVoiceBusy.Set('pma-voice:radio', true))
assert(HumalikeVoiceBusy.Active() and changes[1] == true)
assert(HumalikeVoiceBusy.Set('pma-voice:call', true))
assert(#changes == 1, 'listeners hear the busy state, not every reason')
assert(HumalikeVoiceBusy.Has(':call') and HumalikeVoiceBusy.Has(':radio'))
assert(HumalikeVoiceBusy.Set('pma-voice:radio', false))
assert(HumalikeVoiceBusy.Active(), 'still on the phone')
HumalikeVoiceBusy.ClearPrefix('pma-voice:')
assert(not HumalikeVoiceBusy.Active() and changes[2] == false)
assert(not HumalikeVoiceBusy.Set('bad reason', true))
assert(not HumalikeVoiceBusy.Set(('x'):rep(65), true))

assert(exported.SetVoiceBusy('phone', true))
assert(HumalikeVoiceBusy.Reasons()[1] == 'other_resource:phone', 'export reasons carry the owner')
invoking = nil
assert(not exported.SetVoiceBusy('phone', true))
handlers.onClientResourceStop('unrelated')
assert(HumalikeVoiceBusy.Active())
handlers.onClientResourceStop('other_resource')
assert(not HumalikeVoiceBusy.Active(), 'a stopped resource drops its reasons')
handlers.onClientResourceStop('humalike')
print('busy: ok')
