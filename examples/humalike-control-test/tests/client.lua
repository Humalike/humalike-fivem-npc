local events, nui, commands, timers, requests, messages = {}, {}, {}, {}, {}, {}
local focus=false
function RegisterNetEvent(name,fn) events[name]=fn end
function RegisterNUICallback(name,fn) nui[name]=fn end
function RegisterCommand(name,fn) commands[name]=fn end
function RegisterKeyMapping(name,_,_,key) assert(name=='humalike_npc_test_panel' and key=='F7') end
function AddEventHandler(name,fn) events[name]=fn end
function GetCurrentResourceName() return 'humalike-control-test' end
function TriggerServerEvent(_,id,op,npcId) requests[#requests+1]={id=id,op=op,npcId=npcId} end
function SetTimeout(_,fn) timers[#timers+1]=fn end
function SetNuiFocus(value) focus=value end
function SendNUIMessage(data) messages[#messages+1]=data end
function TriggerEvent() end
dofile('examples/humalike-control-test/client.lua')
commands.humalike_npc_test_panel()
assert(not focus and requests[1].op=='refresh')
events['humalike-control-test:response'](requests[1].id,{ok=false,message='permission_denied'})
assert(not focus)
commands.humalike_npc_test_panel()
events['humalike-control-test:response'](requests[2].id,{ok=true,rows={{npcId='ext'}}})
assert(focus and messages[#messages].rows[1].npcId=='ext')
local count=0
nui.request({operation='bind',npcId='ext'},function(response) count=count+1; assert(not response.ok) end)
timers[#timers]()
assert(count==1)
events['humalike-control-test:response'](requests[3].id,{ok=true})
assert(count==1,'late replies cannot resolve a callback twice')
nui.close({},function(response) assert(response.ok) end)
assert(not focus)
nui.request({operation='delete'},function(response) assert(not response.ok) end)
assert(#requests==3,'closed panel cannot submit operations')
events['humalike-control-test:open']()
assert(focus)
events.onResourceStop('humalike-control-test')
assert(not focus and messages[#messages].type=='close')
print('control panel client: ok')
