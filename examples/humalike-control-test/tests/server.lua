local handlers, commands, replies, entities, states = {}, {}, {}, {}, {}
local allowed, now, created, reads = true, 1000, 0, 0
local vehicle, teleported = 0, nil
local boundModel, currentBucket, position = nil, 0, { x=0, y=0, z=0 }
source = 7
states.ext = { npcId='ext', name='External', kind='external', model='configured_model', active=false, controlledDomains={} }
states.other = { npcId='other', name='Other', kind='external', model='configured_model', active=true, entityOwnerResource='other-resource', controlledDomains={} }
states.static = { npcId='static', kind='static', active=true, controlledDomains={} }
local function ok(value) return {ok=true,value=value} end
exports = { humalike = {} }
function exports.humalike:ListNpcRuntimeStates()
    reads=reads+1
    return ok({states.ext,states.other,states.static})
end
function exports.humalike:GetNpcRuntimeState(id)
    return states[id] and ok(states[id]) or {ok=false,error='npc_not_found'}
end
function exports.humalike:BindNpcEntity(id,net)
    states[id].active=true; states[id].bindingId='binding'; states[id].networkId=net
    states[id].entityOwnerResource='humalike-control-test'
    return ok({id='binding'})
end
function exports.humalike:UnbindNpcEntity()
    states.ext.active=false; states.ext.bindingId=nil
    return ok()
end
function exports.humalike:AcquireNpcControl(id)
    states[id].controlledDomains={movement={leaseId='lease',ownerResource='humalike-control-test'}}
    return ok({id='lease'})
end
function exports.humalike:ReleaseNpcControl()
    states.ext.controlledDomains={}
    return ok()
end
function GetCurrentResourceName() return 'humalike-control-test' end
function RegisterCommand(name,fn) commands[name]=fn end
function RegisterNetEvent(name,fn) handlers[name]=fn end
function AddEventHandler(name,fn) handlers[name]=fn end
function IsPlayerAceAllowed(_,ace) assert(ace=='command.humalike_npc_test'); return allowed end
function GetGameTimer() return now end
function TriggerClientEvent(name,player,id,response) replies[#replies+1]={name=name,player=player,id=id,response=response} end
function GetPlayerPed() return 10 end
function GetEntityCoords(entity) return entity==10 and position or {x=2,y=0,z=0} end
function GetEntityHeading() return 0 end
function GetPlayerRoutingBucket() return currentBucket end
function GetEntityRoutingBucket(entity) return entities[entity].bucket end
function GetHashKey(model) boundModel=model; return 42 end
function CreatePed(_,hash) assert(hash==42); created=created+1; entities[100+created]={bucket=0}; return 100+created end
function SetEntityRoutingBucket(entity,bucket) entities[entity].bucket=bucket end
function SetEntityOrphanMode() end
function NetworkGetNetworkIdFromEntity(entity) return entity+1000 end
function DoesEntityExist(entity) return entity==10 or entities[entity]~=nil end
function GetVehiclePedIsIn() return vehicle end
function SetPlayerRoutingBucket(_, bucket) currentBucket=bucket end
function SetEntityCoords(entity,x,y,z) teleported={entity=entity,x=x,y=y,z=z} end
function DeleteEntity(entity) entities[entity]=nil end
function Wait() end
json={encode=function() return '{}' end}
dofile('examples/humalike-control-test/server.lua')
local sequence=0
local function request(op,id)
    now=now+300; sequence=sequence+1
    handlers['humalike-control-test:request'](sequence,op,id)
    return replies[#replies].response
end
allowed=false
assert(request('refresh').message=='permission_denied' and reads==0)
assert(request('bind','ext').ok==false and created==0)
allowed=true
local rows=request('refresh').rows
assert(#rows==3 and rows[1].npcId=='ext' and rows[1].active==false)
assert(request('bind','static').message=='npc_not_external')
assert(request('bind','other').message=='ped_owned_by_another_resource' and created==0)
assert(request('delete','other').message=='not_a_test_resource_ped')
assert(request('bind','ext').ok and created==1 and boundModel=='configured_model')
assert(request('refresh').rows[1].testPed==true)
assert(request('control','ext').ok)
assert(request('refresh').rows[1].canRelease==true)
assert(request('release','ext').ok)
assert(request('unbind','ext').ok and entities[101]~=nil)
assert(request('refresh').rows[1].testPed and not request('refresh').rows[1].bound)
assert(request('bind','ext').ok and entities[101]==nil and created==2)
position={x=500,y=0,z=0}
assert(request('delete','ext').message=='ped_too_far_or_other_bucket')
position={x=0,y=0,z=0}; currentBucket=3
assert(request('delete','ext').message=='ped_too_far_or_other_bucket')
currentBucket=0
assert(request('delete','ext').ok and entities[102]==nil)
assert(states.ext.active, 'delete intentionally does not call unbind; runtime detaches on entity loss')
states.ext.active=false; states.ext.bindingId=nil
assert(request('bind','ext').ok)
local count=created
handlers['humalike-control-test:request'](sequence+1,'bind','ext')
assert(replies[#replies].response.message=='rate_limited' and created==count)
allowed=false
assert(request('delete','ext').message=='permission_denied')
allowed=true
handlers['humalike:npc:ready']()
assert(request('refresh').rows[1].bound)
handlers.onResourceStop('humalike-control-test')
assert(next(entities)==nil, 'stop cleans up every test-owned entity')
local countBefore=#replies
handlers['humalike-control-test:request']({},'delete','ext')
assert(#replies==countBefore)
assert(request('teleport','ext').message=='npc_ped_unavailable')
entities[900]={bucket=5}; states.static.entity=900; states.static.networkId=1900
assert(request('refresh').rows[3].kind=='static' and request('refresh').rows[3].canTeleport)
assert(request('delete','static').message=='npc_not_external')
allowed=false
assert(request('teleport','static').message=='permission_denied' and teleported==nil)
allowed=true; vehicle=55
assert(request('teleport','static').message=='exit_vehicle_before_teleport' and teleported==nil)
vehicle=0
assert(request('teleport','static').ok and currentBucket==5 and teleported.entity==10)
assert(teleported.x==4 and teleported.z==0.3)
states.other.entity=900; states.other.networkId=1900
assert(request('teleport','other').ok, 'Can visit NPCs owned by other resources')
states.other.kind='ambient'
assert(request('refresh').rows[2].kind=='dynamic')
assert(request('teleport','other').ok, 'Can visit active dynamic NPCs')
assert(request('delete','other').message=='npc_not_external')
states.other.networkId=9999
assert(request('teleport','other').message=='npc_ped_unavailable', 'Reject recycled entity handles')
entities[900]=nil
assert(request('teleport','static').message=='npc_ped_unavailable')
print('control test panel: ok')
