local handlers = {}
local requested = false

function RegisterNetEvent() end
function AddEventHandler(name, callback) handlers[name] = callback end
function CreateThread(callback) callback() end
function Wait() end
function TriggerServerEvent(name)
    requested = name == 'humalike:npc:requestRuntimeControls'
end

dofile('client/runtime_control.lua')

assert(requested == true)
assert(HumalikeNpcRuntimeControl.IsControlled('npc-1', 'speech') == false)
handlers['humalike:npc:runtimeControlSnapshot'](1, {
    ['npc-1'] = { speech = true },
    ['npc-2'] = { all = true },
})
assert(HumalikeNpcRuntimeControl.IsControlled('npc-1', 'speech') == true)
assert(HumalikeNpcRuntimeControl.IsVoiceUnavailable('npc-1') == true)
assert(HumalikeNpcRuntimeControl.IsControlled('npc-1', 'movement') == false)
assert(HumalikeNpcRuntimeControl.IsControlled('npc-2', 'movement') == true)
handlers['humalike:npc:runtimeControlSnapshot'](1, {})
assert(HumalikeNpcRuntimeControl.IsControlled('npc-1', 'speech') == true)

print('runtime_control_client: ok')
