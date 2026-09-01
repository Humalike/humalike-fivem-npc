Config = {
    Integrations = { interaction = 'auto' },
    AmbientControl = {
        InteractionDistance = 3.0,
        RequestCooldownMs = 750,
        StandTaskDurationMs = 2000,
        StandTaskRefreshMs = 500,
    },
    AmbientRevive = { InteractionDistance = 3.0, DurationMs = 5000 },
}

AmbientPeds = {}
AmbientNpcEntries = {}
AmbientInteractionAdapters = {}
local vectorMeta = {}
vectorMeta.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta)
end
vectorMeta.__len = function(v)
    return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end
function vector3(x, y, z)
    return setmetatable({ x = x, y = y, z = z }, vectorMeta)
end


local handlers = {}
local currentOptions
local dead = true
local triggered
local holdThread
local hasControl = true
local taskClears = 0
local standCalls = 0

function RegisterNetEvent() end
function HumalikeDebug() end
function GetCurrentResourceName() return 'humalike' end
function GetInvokingResource() return 'custom-integration' end
function exports() end
function AddEventHandler(name, handler) handlers[name] = handler end
function CreateThread(callback) holdThread = callback end
function DoesEntityExist(entity) return entity == 42 end
function IsEntityDead() return dead end
function IsPedDeadOrDying() return dead end
function StopPedSpeaking() end
function DisablePedPainAudio() end
function GetPlayerServerId() return 7 end
function PlayerId() return 1 end
function TriggerServerEvent(...)
    triggered = { ... }
end
function NetworkHasControlOfEntity() return hasControl end
function SetBlockingOfNonTemporaryEvents() end
function TaskSetBlockingOfNonTemporaryEvents() end
function ClearPedTasksImmediately() end
function ClearPedTasks() taskClears = taskClears + 1 end
function TaskWanderStandard() end
function TaskStandStill(_, duration)
    assert(duration == Config.AmbientControl.StandTaskDurationMs)
    standCalls = standCalls + 1
end
local actionControlled = false
function IsActionControlled() return actionControlled end

AmbientInteractionAdapters.custom = {
    name = 'custom',
    priority = 100,
    Add = function(_, _, options)
        currentOptions = options
        return true
    end,
    Remove = function() currentOptions = nil end,
}
dofile('../integration/client/interactions.lua')
dofile('client/ambient_control.lua')

local entry = {
    entity_id = 42,
    network_id = 12,
    routing_bucket = 0,
    lease_token = 'lease-token',
}
AmbientPeds.npc = 42
AmbientNpcEntries.npc = entry
Config.Wounded = { Enabled = false }
handlers['humalike:npc:ambientPedAssigned']('npc', 42)

assert(#currentOptions == 1 and currentOptions[1].text == 'Pomóż wstać')
assert(currentOptions[1].canInteract(42), 'available on a server without the lifecycle')
currentOptions[1].onSelect()
assert(triggered[1] == 'humalike:npc:beginAmbientRevive')
assert(triggered[2] == 42)
assert(triggered[3] == 'npc')
assert(triggered[4] == 'lease-token')
Config.Wounded = { Enabled = true }
handlers['humalike:npc:npcDownedChanged']('npc')
assert(currentOptions == nil, 'movement control is voice-only and registers no ordinary wheel')

HumalikeDownedState = function() return 'wounded' end
HumalikeTreatmentOptions = function() return { { text = 'Reanimuj' } } end
handlers['humalike:npc:npcDownedChanged']('npc')
assert(#currentOptions == 1 and currentOptions[1].text == 'Reanimuj',
    'a body wheel holds only the treatment options')

HumalikeTreatmentOptions = function() return {} end
currentOptions = nil
handlers['humalike:npc:treatmentAccessChanged']()
assert(currentOptions == nil, 'a bystander gets no wheel on a body at all')
HumalikeDownedState = function() return nil end
HumalikeTreatmentOptions = nil
Config.Wounded = { Enabled = false }
handlers['humalike:npc:npcDownedChanged']('npc')
assert(#currentOptions == 1 and currentOptions[1].text == 'Pomóż wstać')

handlers['humalike:npc:ambientPedRemoved']('npc', 42, entry)
dead = false
AmbientPeds.npc = 42
AmbientNpcEntries.npc = entry
handlers['humalike:npc:ambientPedAssigned']('npc', 42)
assert(#currentOptions == 1 and not currentOptions[1].canInteract(42))

handlers['humalike:npc:ambientControlChanged']('42', {
    mode = 'held', controller_source = 7,
})

local function runHoldIteration()
    local waitCount = 0
    local previousWait = Wait
    Wait = function()
        waitCount = waitCount + 1
        if waitCount > 2 then error('stop thread') end
    end
    local ok, message = pcall(holdThread)
    Wait = previousWait
    assert(not ok and tostring(message):find('stop thread', 1, true))
end

runHoldIteration()
assert(taskClears == 1 and standCalls == 1)
runHoldIteration()
assert(taskClears == 1 and standCalls == 2)

hasControl = false
runHoldIteration()
hasControl = true
runHoldIteration()
assert(taskClears == 2 and standCalls == 3)
actionControlled = true
runHoldIteration()
assert(taskClears == 2 and standCalls == 3)
actionControlled = false
runHoldIteration()
assert(taskClears == 2 and standCalls == 4)
AmbientInteractionAdapters['ox_target'] = {
    resource = 'ox_target',
    Available = function() return true end,
    Add = function() return true end,
    Remove = function() end,
}

assert(HumalikeInteractionAdapter() == AmbientInteractionAdapters.custom,
    'the highest-priority available custom provider wins')

AmbientInteractionAdapters.custom.Available = function() return false end
assert(HumalikeInteractionAdapter() == AmbientInteractionAdapters['ox_target'],
    'an unavailable custom provider falls back rather than going dark')

assert(HumalikeIsInteractionResource('ox_target'), 'a late-starting wheel is recognised')
assert(not HumalikeIsInteractionResource('some-other-resource'))

AmbientInteractionAdapters['ox_target'].Available = function() return false end
assert(HumalikeInteractionAdapter() == nil,
    'nothing can draw a menu, so nothing claims it can')
Config.Wounded = { LingerRadius = 20.0 }
local progressCalls = {}
AmbientInteractionAdapters['ox_target'].Available = function() return true end
AmbientInteractionAdapters['ox_target'].Progress = function(duration, label)
    progressCalls[#progressCalls + 1] = { duration = duration, label = label }
    return true
end

function GetEntityCoords() return vector3(0, 0, 0) end
function PlayerPedId() return 1 end
function DoesEntityExist() return true end

assert(HumalikeInteractionProgress(10000, 'Leczenie', 42) == true)
assert(#progressCalls == 1 and progressCalls[1].duration == 10000)
assert(progressCalls[1].label == 'Leczenie')
AmbientInteractionAdapters['ox_target'].Progress = function() return false end
assert(HumalikeInteractionProgress(10000, 'Leczenie', 42) == false)
AmbientInteractionAdapters['ox_target'].Progress = function() return true end
GetEntityCoords = function(entity) return entity == 1 and vector3(0, 0, 0) or vector3(99, 0, 0) end
assert(HumalikeInteractionProgress(10000, 'Leczenie', 42) == false,
    'out of reach at the end is not a treatment')
