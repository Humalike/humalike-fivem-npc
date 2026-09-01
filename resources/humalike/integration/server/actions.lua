HumalikeActions = {}

function HumalikeActions.Supported()
    local provider = HumalikeSelectedProvider('actions')
    local result = {}
    if not provider then return result end
    for _, action in ipairs(provider.SupportedActions or {}) do
        result[#result + 1] = action
    end
    return result
end

function HumalikeActions.Run(action, source, coords, params)
    local ok, value = HumalikeProviderCall(
        'actions', 'RunAction', action, source, coords, params)
    return ok and value == true
end

function GetSupportedActions()
    local result, seen = {}, {}
    local function add(action)
        if type(action) == 'string' and not seen[action] then
            result[#result + 1] = action
            seen[action] = true
        end
    end
    for _, action in ipairs(Config.SupportedActions or {}) do add(action) end
    if HumalikeInventory.Available() then add('give_item') end
    for _, action in ipairs(HumalikeActions.Supported()) do add(action) end
    return result
end

function IsSupportedAction(action)
    for _, supported in ipairs(GetSupportedActions()) do
        if supported == action then return true end
    end
    return false
end
