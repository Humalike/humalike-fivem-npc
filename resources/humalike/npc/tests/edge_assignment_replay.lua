local handlers, rosterCallbacks, bindingCallbacks = {}, {}, {}
local assignment = 'edge-a:7'
local entityState = {}
local consolePrint = print

HumaLike = {
    RuntimeCredentials = function()
        return { bootId = 'fivem-boot' }
    end,
    EdgeAssignmentKey = function() return assignment end,
    IsCurrentEdgeAssignment = function(expected) return expected == assignment end,
}
HumalikeNpcEntityOwnership = {
    ExternalEntity = function() return nil end,
    IsDespawned = function() return false end,
    SetRuntimeToken = function() end,
    Reconcile = function() end,
    ForgetNpc = function() end,
    DefinitionChanged = function() end,
}
HumalikeHttp = {
    PostAction = function(name, _, callback)
        if name == 'get_npc_roster' then
            rosterCallbacks[#rosterCallbacks + 1] = callback
        elseif name == 'upsert_npc_runtime_binding' then
            bindingCallbacks[#bindingCallbacks + 1] = callback
        elseif name == 'report_capabilities' then
            callback(true, 200, {})
        end
    end,
}
Config = { RosterSyncIntervalMs = 60000 }
NpcPoses = {}

function AddEventHandler(name, callback)
    handlers[name] = handlers[name] or {}
    handlers[name][#handlers[name] + 1] = callback
end
function TriggerEvent(name, payload)
    for _, callback in ipairs(handlers[name] or {}) do callback(payload) end
end
function TriggerClientEvent() end
function CreateThread() end
function RegisterCommand() end
function RegisterNetEvent() end
function GetSupportedActions() return {} end
function GetCurrentResourceName() return 'humalike' end
function NetworkGetNetworkIdFromEntity() return 53 end
function NetworkGetEntityOwner() return 7 end
function GetEntityRoutingBucket() return 0 end
function GetEntityModel() return 10 end
function DoesEntityExist(entity) return entity == 303 end
function CreatePed() return 303 end
function SetEntityRoutingBucket() end
function SetEntityOrphanMode() end
function GetHashKey() return 10 end
function Wait() end
function DeleteEntity() end
function Entity()
    entityState.set = function(_, key, value) entityState[key] = value end
    return { state = entityState }
end
function HumalikeDebug() end
function ForgetNpcPose() end

local function roster(language)
    return {
        npcs = {
            {
                npc_id = 'static-1', name = 'Jan', type = 'static',
                model = 'model-one', x = 1, y = 2, z = 3, heading = 90,
                language = language, voice_muted = false,
            },
        },
    }
end

dofile('server/persistent.lua')
dofile('server/npc.lua')
dofile('server/main.lua')

TriggerEvent('humalike:core:ready', { generation = 1 })
rosterCallbacks[1](true, 200, roster('pl'))
bindingCallbacks[1](true, 200, { runtime_token = 'edge-a-token' })
assert(NpcRegistry['static-1'].runtime_token == 'edge-a-token')

assignment = 'edge-b:8'
TriggerEvent('humalike:runtime:edgeChanged', { generation = 8 })
assert(#bindingCallbacks == 2 and #rosterCallbacks == 2)
rosterCallbacks[2](true, 200, roster('en'))
local replacementEntry = NpcRegistry['static-1']
assert(replacementEntry.language == 'en' and replacementEntry.runtime_token == nil)
bindingCallbacks[2](true, 200, { runtime_token = 'edge-b-token' })
assert(NpcRegistry['static-1'] == replacementEntry)
assert(replacementEntry.runtime_token == 'edge-b-token',
    'roster replacement must receive the new edge binding token')
assert(entityState.humalike_runtime_token == 'edge-b-token')

consolePrint('edge_assignment_replay: ok')
