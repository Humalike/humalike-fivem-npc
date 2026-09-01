AmbientInteractionAdapters = AmbientInteractionAdapters or {}

local RESOURCE = 'qb-target'
local registered = {}

local function iconName(icon)
    if type(icon) ~= 'string' or icon == '' then return nil end
    if icon:find('%s') then return icon end
    return 'fas fa-' .. icon
end

AmbientInteractionAdapters[RESOURCE] = {
    name = RESOURCE,
    resource = RESOURCE,
    priority = 10,

    Available = function()
        return GetResourceState(RESOURCE) == 'started'
    end,

    Add = function(id, entity, options)
        if GetResourceState(RESOURCE) ~= 'started' then return false end
        if not entity or not DoesEntityExist(entity) or #options == 0 then return false end
        local mapped, labels = {}, {}
        for index, option in ipairs(options) do
            local label = option.text or ('HumaLike interaction %d'):format(index)
            labels[index] = label
            mapped[index] = {
                icon = iconName(option.icon),
                label = label,
                canInteract = option.canInteract,
                action = function(target)
                    if option.onSelect then option.onSelect(target) end
                end,
            }
        end
        local ok = pcall(function()
            exports[RESOURCE]:AddTargetEntity(entity, {
                options = mapped,
                distance = (Config.AmbientControl or {}).InteractionDistance or 3.0,
            })
        end)
        if not ok then return false end
        registered[id] = { entity = entity, labels = labels }
        return true
    end,

    Remove = function(id)
        local entry = registered[id]
        registered[id] = nil
        if not entry or GetResourceState(RESOURCE) ~= 'started' then return end
        pcall(function()
            exports[RESOURCE]:RemoveTargetEntity(entry.entity, entry.labels)
        end)
    end,
}
