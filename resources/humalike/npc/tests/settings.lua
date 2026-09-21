-- The server's convars reach the client even when written with `set`.
local convars = {
    humalike_interaction = 'ox_target',
    humalike_npc_labels_default_language = 'de',
    humalike_world_npc_report_radius = '80',
    humalike_npc_wounded_enabled = 'false',
}
function GetConvar(name, default)
    local value = convars[name]
    if value == nil then return default end
    return value
end
function GetConvarInt(name, default)
    local value = convars[name]
    if value == nil then return default end
    return math.tointeger(tonumber(value)) or default
end
function GetHashKey(name)
    local hash = 5381
    for index = 1, #name do hash = (hash * 33 + name:byte(index)) % 4294967296 end
    return hash
end

dofile('config/convars.lua')
dofile('config/shared.lua')
dofile('../world/config.lua')
dofile('config/wounds.lua')

-- Server side: the snapshot carries every set convar the config reads.
local snapshot = HumalikeConvarSnapshot()
assert(snapshot.humalike_interaction == 'ox_target')
assert(snapshot.humalike_npc_labels_default_language == 'de')
assert(snapshot.humalike_world_npc_report_radius == '80')
assert(snapshot.humalike_npc_wounded_enabled == 'false')
assert(snapshot.humalike_player == nil, 'an unset convar is not sent; the client keeps its default')

-- Client side: nothing was replicated, so local reads only see defaults.
convars = {}
for _, build in ipairs(HumalikeConvars.builders) do build() end
assert(Config.Integrations.interaction == 'auto')
assert(Config.NpcLabels.DefaultLanguage == 'en')
assert(WorldConfig.npcEdge.reportRadius == 150.0)
assert(Config.Wounded.Enabled == true)

assert(HumalikeApplyConvarSnapshot(snapshot))
assert(Config.Integrations.interaction == 'ox_target')
assert(Config.NpcLabels.DefaultLanguage == 'de')
assert(WorldConfig.npcEdge.reportRadius == 80.0)
assert(Config.Wounded.Enabled == false)
assert(Config.Integrations.player == 'auto', 'unsent values keep the client default')
assert(Config.UiLanguage == 'en')

assert(HumalikeApplyConvarSnapshot({ humalike_interaction = { nested = true } }) == false)
assert(Config.Integrations.interaction == 'ox_target', 'a rejected snapshot changes nothing')
assert(HumalikeApplyConvarSnapshot({ humalike_interaction = 'a\nb' }) == false)
assert(HumalikeApplyConvarSnapshot({ not_registered = 'x' }))
assert(HumalikeConvars.overrides.not_registered == nil, 'unknown names are ignored')
assert(Config.Integrations.interaction == 'auto', 'an empty snapshot restores local defaults')
assert(HumalikeApplyConvarSnapshot({ humalike_world_npc_report_radius = 42 }))
assert(WorldConfig.npcEdge.reportRadius == 42.0, 'numbers are accepted for integer settings')
assert(HumalikeApplyConvarSnapshot({ humalike_world_npc_report_radius = '80.5' }))
assert(WorldConfig.npcEdge.reportRadius == 80.0, 'a decimal floors like GetConvarInt')
assert(HumalikeApplyConvarSnapshot('nope') == false)
print('settings: ok')
