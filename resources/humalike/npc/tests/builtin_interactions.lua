Config = { AmbientControl = { InteractionDistance = 3.0 } }
AmbientInteractionAdapters = {}

local thread, selected, helpText, released = nil, false, nil, true
local vectorMeta = {}
vectorMeta.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vectorMeta)
end
vectorMeta.__len = function(value)
    return math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
end
local function vector(x, y, z) return setmetatable({ x = x, y = y, z = z }, vectorMeta) end

function CreateThread(callback) thread = callback end
function PlayerPedId() return 1 end
function DoesEntityExist(entity) return entity == 1 or entity == 42 end
function GetEntityCoords(entity)
    return entity == 1 and vector(0, 0, 0) or vector(1, 0, 0)
end
function BeginTextCommandDisplayHelp() end
function AddTextComponentSubstringPlayerName(text) helpText = text end
function EndTextCommandDisplayHelp() end
function IsControlJustReleased(_, control)
    if control ~= 38 then return false end
    local value = released
    released = false
    return value
end
function Wait() error('stop loop') end

dofile('../integration/providers/builtin/client.lua')

local provider = AmbientInteractionAdapters.builtin
assert(provider.Add('npc-1', 42, {
    {
        text = 'interact',
        canInteract = function(entity) return entity == 42 end,
        onSelect = function(entity) selected = entity == 42 end,
    },
}))
local ok, message = pcall(thread)
assert(not ok and tostring(message):find('stop loop', 1, true))
assert(selected and helpText:find('interact', 1, true))

provider.Remove('npc-1')
helpText = nil
ok, message = pcall(thread)
assert(not ok and tostring(message):find('stop loop', 1, true))
assert(helpText == nil)

print('builtin_interactions: ok')
