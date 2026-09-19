HumalikeActions = {}

function HumalikeActions.Supported()
    local provider = HumalikeSelectedProvider('actions')
    local result = {}
    if not provider then return result end
    for _, action in ipairs(provider.SupportedActions or {}) do
        result[#result + 1] = action
    end
    -- The server's own actions, namespaced, in a stable order.
    local custom = {}
    for key in pairs(provider.Actions or {}) do custom[#custom + 1] = key end
    table.sort(custom)
    for _, key in ipairs(custom) do result[#result + 1] = provider.Namespace .. ':' .. key end
    return result
end

-- The local key and definition behind a namespaced action key the backend
-- pushes, or nil for a built-in action.
function HumalikeActions.Custom(wireKey)
    local provider = HumalikeSelectedProvider('actions')
    if not provider or not provider.Namespace or type(wireKey) ~= 'string' then return nil end
    local key = wireKey:match('^' .. provider.Namespace .. ':([a-z][a-z0-9_]*)$')
    local definition = key and provider.Actions[key] or nil
    if not definition then return nil end
    return key, definition
end

-- nil for an empty table: it would encode as a JSON array where the backend
-- expects an object, and every such field defaults there anyway.
local function mapOrNil(value)
    if next(value) == nil then return nil end
    return value
end

-- What report_capabilities sends beside the keys: the server's declarations
-- in the backend's wire shape. Fixed params stay here -- the model never
-- sees them and the backend has no use for them.
function HumalikeActions.Declarations()
    local provider = HumalikeSelectedProvider('actions')
    local actions, observations = {}, {}
    if not provider or not provider.Namespace then return actions, observations end
    local prefix = provider.Namespace .. ':'
    local keys = {}
    for key in pairs(provider.Actions or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local action = provider.Actions[key]
        local requires = {}
        for index, rule in ipairs(action.requires) do
            requires[index] = {
                observation = prefix .. rule.observation, where = mapOrNil(rule.where),
                within_s = rule.within_s, consume = rule.consume,
            }
        end
        local paramsFrom = {}
        for name, source in pairs(action.params_from) do
            paramsFrom[name] = prefix .. source.observation .. '.' .. source.field
        end
        actions[#actions + 1] = {
            key = prefix .. key, name = action.name, description = action.description,
            params = mapOrNil(action.params), preconditions = requires,
            locked_hint = action.locked_hint, limit = action.limit,
            auto = action.auto or nil,
            params_from = mapOrNil(paramsFrom),
        }
    end
    keys = {}
    for key in pairs(provider.Observations or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        observations[#observations + 1] = {
            key = prefix .. key, fields = mapOrNil(provider.Observations[key].fields),
        }
    end
    return actions, observations
end

-- The wire key and definition of a declared observation, or nil when the
-- selected provider declares no such thing.
function HumalikeActions.Observation(key)
    local provider = HumalikeSelectedProvider('actions')
    local definition = provider and type(key) == 'string' and provider.Observations[key] or nil
    if not definition then return nil end
    return provider.Namespace .. ':' .. key, definition
end

-- Exactly `true` is a deed done; anything else is a refusal, and a refused
-- deed is pushed again, so a `1` or an `'ok'` would be performed twice.
-- Said once, the first time it happens.
local warnedReturn = false
function HumalikeActions.Run(action, source, coords, params)
    local ok, value = HumalikeProviderCall(
        'actions', 'RunAction', action, source, coords, params)
    if ok and type(value) ~= 'boolean' and not warnedReturn then
        warnedReturn = true
        print(('[humalike] actions provider RunAction(%s) returned %s; '
            .. 'return true to accept, anything else rejects'):format(action, type(value)))
    end
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
