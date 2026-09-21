-- Client asks, server answers once per second per player, client rebuilds.
local handlers, sent, events, serverEvents = {}, {}, {}, {}
local now = 0
local thread
function RegisterNetEvent() end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerEvent(name, ...) events[#events + 1] = name end
function TriggerServerEvent(name) serverEvents[#serverEvents + 1] = name end
function TriggerClientEvent(name, target, payload) sent[#sent + 1] = { name, target, payload } end
function GetGameTimer() return now end
function CreateThread(fn) thread = fn end
function Wait(ms) now = now + ms end
function GetConvar(_, default) return default end
function GetConvarInt(_, default) return default end

dofile('config/convars.lua')
dofile('config/shared.lua')

-- server
dofile('server/settings.lua')
source = 7
handlers['humalike:settings:request']()
assert(#sent == 1 and sent[1][1] == 'humalike:settings' and sent[1][2] == 7)
assert(type(sent[1][3]) == 'table')
handlers['humalike:settings:request']()
assert(#sent == 1, 'a repeat inside one second is dropped')
now = 1500
handlers['humalike:settings:request']()
assert(#sent == 2)
handlers.playerDropped()
source = 0
handlers['humalike:settings:request']()
assert(#sent == 2, 'the console is not a player')

-- client
dofile('client/settings.lua')
assert(HumalikeSettings.applied == false)
handlers['humalike:settings']({ humalike_interaction = 'qb_target' })
assert(HumalikeSettings.applied == true)
assert(Config.Integrations.interaction == 'qb_target')
assert(events[#events] == 'humalike:settings:applied')
handlers['humalike:settings']('bad')
assert(Config.Integrations.interaction == 'qb_target', 'a bad payload is ignored')

HumalikeSettings.applied = false
local requests = 0
TriggerServerEvent = function(name)
    requests = requests + 1
    if requests == 3 then HumalikeSettings.applied = true end
end
thread()
assert(requests == 3, 'the client keeps asking until the server answers')

HumalikeSettings.applied = false
now = 0
assert(HumalikeSettings.Wait(1000) == false and now == 1000, 'a silent server delays the caller by maxMs, no more')
now = 0
assert(HumalikeSettings.Wait(30) == false and now == 30, 'a short bound is honoured')
now = 0
local waited = 0
Wait = function(ms) now = now + ms; waited = waited + 1; HumalikeSettings.applied = true end
assert(HumalikeSettings.Wait(5000) == true and waited == 1, 'the wait ends when the snapshot lands')
print('settings_sync: ok')
