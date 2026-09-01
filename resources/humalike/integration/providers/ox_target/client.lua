AmbientInteractionAdapters = AmbientInteractionAdapters or {}

local RESOURCE = 'ox_target'
local registered = {}

AmbientInteractionAdapters[RESOURCE] = {
    name = RESOURCE,
    resource = RESOURCE,
    priority = 10,

    Available = function()
        return GetResourceState(RESOURCE) == 'started'
    end,

    Add = function(id, entity, options)
        if GetResourceState(RESOURCE) ~= 'started' then return false end
        if not entity or not DoesEntityExist(entity) then return false end
        if #options == 0 then return false end
        local mapped, names = {}, {}
        for index, option in ipairs(options) do
            local name = ('%s:%d'):format(id, index)
            names[index] = name
            mapped[index] = {
                name = name,
                label = option.text,
                icon = option.icon,
                distance = (Config.AmbientControl or {}).InteractionDistance or 3.0,
                canInteract = option.canInteract,
                onSelect = option.onSelect,
            }
        end
        local ok = pcall(function()
            exports[RESOURCE]:addLocalEntity(entity, mapped)
        end)
        if not ok then return false end
        registered[id] = { entity = entity, names = names }
        return true
    end,

    Remove = function(id)
        local entry = registered[id]
        registered[id] = nil
        if not entry or GetResourceState(RESOURCE) ~= 'started' then return end
        pcall(function()
            exports[RESOURCE]:removeLocalEntity(entry.entity, entry.names)
        end)
    end,
}
