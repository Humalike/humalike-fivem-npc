
local function randomHex(length)
    local value = ''
    for _ = 1, length do value = value .. ('%x'):format(math.random(0, 15)) end
    return value
end

local function runtimeEpoch()
    return randomHex(8) .. '-' .. randomHex(4) .. '-4' .. randomHex(3)
        .. '-8' .. randomHex(3) .. '-' .. randomHex(12)
end

HumalikeProviders = {
    apiVersion = 1,
    runtimeEpoch = runtimeEpoch(),
    registered = {},
    selected = {},
    resolution = {},
}

local DOMAINS = {
    player = {
        required = { 'GetCharacterId', 'GetCharacterName', 'IsCharacterLoaded' },
        optional = { 'HasJob', 'Notify' },
    },
    inventory = { required = { 'AddItem' } },
    dispatch = { required = { 'Report' } },
    -- RunAction is required only once the provider implements an action (see
    -- validateDescriptor): an integration that only reports observations has
    -- nothing to run.
    actions = { required = {}, optional = { 'RunAction' } },
}

local OBSERVATION_LIMITS = { observations = 32, fields = 8, template = 400, description = 200 }
local OBSERVATION_FIELD_TYPES = { string = true, integer = true, number = true, boolean = true }
local OBSERVATION_LANGUAGES = { en = true, pl = true }
local ACTION_LIMITS = {
    actions = 32, name = 80, description = 400, params = 4, enum = 16, fixed = 16,
    requires = 4, hint = 300, withinMin = 5, withinMax = 3600,
}
local ACTION_PARAM_TYPES = { string = true, integer = true, boolean = true }

for domain in pairs(DOMAINS) do HumalikeProviders.registered[domain] = {} end

local function providerSetting(domain)
    local integrations = Config.Integrations or {}
    return tostring(integrations[domain] or 'auto'):lower()
end

local function validName(value)
    return type(value) == 'string' and value:match('^[%w_.-]+$') ~= nil
        and value == value:lower() and value ~= 'none' and #value <= 64
end

local function callable(value)
    return type(value) == 'function' or type(value) == 'table'
end

local function availability(provider)
    if provider.Available == nil then return true, nil end
    local result = table.pack(pcall(provider.Available))
    if not result[1] then return false, ('availability_error:%s'):format(tostring(result[2])) end
    if result[2] == true then return true, nil end
    local reason = type(result[3]) == 'string' and result[3] or 'unavailable'
    return false, reason
end

local function nowMs()
    return type(GetGameTimer) == 'function' and GetGameTimer() or os.time() * 1000
end

local function providerFailure(domain, provider, method, message)
    local failure = provider.failure or { count = 0, suppressed = 0 }
    local now = nowMs()
    failure.count = failure.count + 1
    failure.method = method
    failure.message = tostring(message)
    failure.at = now
    if not failure.reportedAt or now - failure.reportedAt >= 10000 then
        local suffix = failure.suppressed > 0
            and (' (%d suppressed)'):format(failure.suppressed) or ''
        print(('[humalike] %s provider %s.%s failed: %s%s'):format(
            domain, provider.name, method, failure.message, suffix))
        failure.reportedAt = now
        failure.suppressed = 0
    else
        failure.suppressed = failure.suppressed + 1
    end
    provider.failure = failure
    local resolution = HumalikeProviders.resolution[domain]
    if HumalikeProviders.selected[domain] == provider and resolution then
        resolution.state = 'degraded'
        resolution.reason = ('%s callback failed'):format(method)
    end
end

local function providerSuccess(domain, provider)
    if not provider.failure then return end
    provider.failure = nil
    local resolution = HumalikeProviders.resolution[domain]
    if HumalikeProviders.selected[domain] == provider and resolution then
        resolution.state = 'selected'
        resolution.reason = nil
    end
end

local function candidateStatus(domain)
    local candidates = {}
    for name, provider in pairs(HumalikeProviders.registered[domain]) do
        local isAvailable, reason = availability(provider)
        candidates[#candidates + 1] = {
            name = name,
            ownerResource = provider.ownerResource,
            priority = provider.priority,
            available = isAvailable,
            reason = reason,
            state = not isAvailable and 'unavailable'
                or provider.failure and 'degraded' or 'available',
            failure = provider.failure and {
                count = provider.failure.count,
                method = provider.failure.method,
                message = provider.failure.message,
                at = provider.failure.at,
            } or nil,
        }
    end
    table.sort(candidates, function(left, right)
        if left.priority ~= right.priority then return left.priority > right.priority end
        return left.name < right.name
    end)
    return candidates
end

local function resolve(domain)
    local setting = providerSetting(domain)
    local previous = HumalikeProviders.selected[domain]
    local eligible, highestPriority = {}, nil

    for name, provider in pairs(HumalikeProviders.registered[domain]) do
        local isAvailable = availability(provider)
        if isAvailable and (setting == 'auto' or setting == name) then
            if setting ~= 'auto' then
                eligible = { provider }
                break
            end
            if highestPriority == nil or provider.priority > highestPriority then
                highestPriority = provider.priority
                eligible = { provider }
            elseif provider.priority == highestPriority then
                eligible[#eligible + 1] = provider
            end
        end
    end

    local selected, state, reason
    if #eligible == 1 then
        selected = eligible[1]
        state = selected.failure and 'degraded' or 'selected'
        reason = selected.failure and ('%s callback failed'):format(
            selected.failure.method) or nil
    elseif #eligible > 1 then
        state, reason = 'ambiguous', 'multiple providers share the highest priority'
    elseif setting == 'none' then
        state = 'disabled'
    elseif setting == 'auto' then
        state, reason = 'unavailable', 'no available provider'
    else
        state, reason = 'unavailable', ('configured provider %s is unavailable'):format(setting)
    end

    HumalikeProviders.selected[domain] = selected
    HumalikeProviders.resolution[domain] = {
        setting = setting,
        state = state,
        reason = reason,
    }

    if previous == selected then return end
    print(('[humalike] %s provider: %s (%s)'):format(
        domain, selected and selected.name or 'none', state))
    TriggerEvent('humalike:providers:changed', domain,
        selected and selected.name or nil, previous and previous.name or nil)
end

local function validateDescriptor(domain, descriptor)
    local contract = DOMAINS[domain]
    if not contract then return false, 'unknown provider domain' end
    if type(descriptor) ~= 'table' or not validName(descriptor.name) then
        return false, 'invalid provider descriptor'
    end
    if descriptor.apiVersion ~= HumalikeProviders.apiVersion then
        return false, 'unsupported provider API version'
    end
    if type(descriptor.priority) ~= 'number' or descriptor.priority ~= descriptor.priority
        or math.abs(descriptor.priority) > 100000 then return false, 'invalid priority' end
    for _, method in ipairs(contract.required) do
        if not callable(descriptor[method]) then return false, ('invalid %s'):format(method) end
    end
    for _, method in ipairs(contract.optional or {}) do
        if descriptor[method] ~= nil and not callable(descriptor[method]) then
            return false, ('invalid %s'):format(method)
        end
    end
    if descriptor.Available ~= nil and not callable(descriptor.Available) then
        return false, 'invalid Available'
    end
    if domain == 'actions' then
        if type(descriptor.SupportedActions) ~= 'table' then
            return false, 'missing SupportedActions'
        end
        if next(descriptor.SupportedActions) ~= nil and not callable(descriptor.RunAction) then
            return false, 'invalid RunAction'
        end
        if descriptor.Namespace ~= nil and (type(descriptor.Namespace) ~= 'string'
            or not descriptor.Namespace:match('^[a-z][a-z0-9]+$')
            or #descriptor.Namespace > 16) then
            return false, 'invalid Namespace'
        end
        if descriptor.Observations ~= nil then
            if type(descriptor.Observations) ~= 'table' then return false, 'invalid Observations' end
            if next(descriptor.Observations) ~= nil and not descriptor.Namespace then
                return false, 'missing Namespace'
            end
        end
        if descriptor.Actions ~= nil then
            if type(descriptor.Actions) ~= 'table' then return false, 'invalid Actions' end
            if next(descriptor.Actions) ~= nil then
                if not descriptor.Namespace then return false, 'missing Namespace' end
                if not callable(descriptor.RunAction) then return false, 'invalid RunAction' end
            end
        end
    end
    return true
end

local function cleanTemplate(value, maxLength)
    if type(value) ~= 'string' or value:find('%c') then return nil end
    value = value:match('^%s*(.-)%s*$')
    local length = utf8.len(value)
    if value == '' or not length or length > maxLength then return nil end
    return value
end

-- A declared observation: the fields the script will report and the line the
-- NPC reads, per language. Validated here, at RegisterProvider, so a typo
-- surfaces in the integration's own console instead of as a silent drop later.
local function normalizedObservation(key, definition)
    if type(key) ~= 'string' or not key:match('^[a-z][a-z0-9_]*$') or #key > 32 then
        return nil, 'invalid observation key'
    end
    if type(definition) ~= 'table' or (definition.fields ~= nil
        and type(definition.fields) ~= 'table') then
        return nil, ('invalid observation %s'):format(key)
    end
    local fields, fieldCount = {}, 0
    for name, fieldType in pairs(definition.fields or {}) do
        if type(name) ~= 'string' or not name:match('^[a-z][a-z0-9_]*$') or #name > 32
            or not OBSERVATION_FIELD_TYPES[fieldType] then
            return nil, ('invalid field %s in observation %s'):format(tostring(name), key)
        end
        fields[name] = fieldType
        fieldCount = fieldCount + 1
        if fieldCount > OBSERVATION_LIMITS.fields then
            return nil, ('too many fields in observation %s'):format(key)
        end
    end
    if type(definition.template) ~= 'table' or next(definition.template) == nil then
        return nil, ('missing template in observation %s'):format(key)
    end
    local template = {}
    for language, text in pairs(definition.template) do
        text = OBSERVATION_LANGUAGES[language] and cleanTemplate(text, OBSERVATION_LIMITS.template)
        if not text then return nil, ('invalid template in observation %s'):format(key) end
        for placeholder in text:gmatch('{([^{}]*)}') do
            if not fields[placeholder] then
                return nil, ('unknown placeholder {%s} in observation %s'):format(placeholder, key)
            end
        end
        -- A brace left over once every {placeholder} is taken out is a typo
        -- that would otherwise reach the NPC verbatim.
        if text:gsub('{[^{}]*}', ''):find('[{}]') then
            return nil, ('invalid template in observation %s'):format(key)
        end
        template[language] = text
    end
    local description = definition.description
    if description ~= nil
        and not cleanTemplate(description, OBSERVATION_LIMITS.description) then
        return nil, ('invalid description in observation %s'):format(key)
    end
    return { fields = fields, template = template, description = description }
end

local function scalar(value)
    local kind = type(value)
    return kind == 'string' or kind == 'number' or kind == 'boolean'
end

-- A server-defined action: what the model reads, what it may fill in, what
-- the script fixes, and which reported facts must precede it. Mirrors the
-- backend contract so a mistake is refused here, at RegisterProvider, in the
-- integration's own console.
local function normalizedAction(key, definition, observations)
    if type(key) ~= 'string' or not key:match('^[a-z][a-z0-9_]*$') or #key > 32 then
        return nil, 'invalid action key'
    end
    if type(definition) ~= 'table' then return nil, ('invalid action %s'):format(key) end
    local name = cleanTemplate(definition.name, ACTION_LIMITS.name)
    local description = cleanTemplate(definition.description, ACTION_LIMITS.description)
    if not name then return nil, ('invalid name in action %s'):format(key) end
    if not description or description:find('[%[%]]') then
        return nil, ('invalid description in action %s'):format(key)
    end
    for _, collection in ipairs({ 'params', 'fixed', 'requires', 'locked_hint', 'limit',
        'uses_stock', 'params_from' }) do
        if definition[collection] ~= nil and type(definition[collection]) ~= 'table' then
            return nil, ('invalid %s in action %s'):format(collection, key)
        end
    end
    local params, paramCount = {}, 0
    for paramName, spec in pairs(definition.params or {}) do
        if type(paramName) ~= 'string' or not paramName:match('^[a-z][a-z0-9_]*$')
            or #paramName > 32 or paramName == 'player_id' or type(spec) ~= 'table'
            or not ACTION_PARAM_TYPES[spec.type] then
            return nil, ('invalid param %s in action %s'):format(tostring(paramName), key)
        end
        local param = { type = spec.type, required = spec.required == true }
        if spec.enum ~= nil then
            if type(spec.enum) ~= 'table' or #spec.enum == 0
                or #spec.enum > ACTION_LIMITS.enum or spec.type == 'boolean' then
                return nil, ('invalid enum for %s in action %s'):format(paramName, key)
            end
            param.enum = {}
            for index, choice in ipairs(spec.enum) do
                local valid = (spec.type == 'string' and type(choice) == 'string'
                    and choice:match('^[a-z0-9_.-]+$') and #choice <= 32)
                    or (spec.type == 'integer' and math.type(choice) == 'integer')
                if not valid then
                    return nil, ('invalid enum for %s in action %s'):format(paramName, key)
                end
                param.enum[index] = choice
            end
        end
        if spec.description ~= nil then
            param.description = cleanTemplate(spec.description, 120)
            if not param.description then
                return nil, ('invalid description for %s in action %s'):format(paramName, key)
            end
        end
        params[paramName] = param
        paramCount = paramCount + 1
        if paramCount > ACTION_LIMITS.params then
            return nil, ('too many params in action %s'):format(key)
        end
    end
    local fixed, fixedCount = {}, 0
    for fixedName, value in pairs(definition.fixed or {}) do
        if type(fixedName) ~= 'string' or params[fixedName] or not scalar(value) then
            return nil, ('invalid fixed param %s in action %s'):format(tostring(fixedName), key)
        end
        fixed[fixedName] = value
        fixedCount = fixedCount + 1
        if fixedCount > ACTION_LIMITS.fixed then
            return nil, ('too many fixed params in action %s'):format(key)
        end
    end
    local requires = {}
    for index, rule in ipairs(definition.requires or {}) do
        if index > ACTION_LIMITS.requires then
            return nil, ('too many requirements in action %s'):format(key)
        end
        local observation = type(rule) == 'table' and observations[rule.observation] or nil
        if not observation then
            return nil, ('unknown observation in requirement %d of action %s'):format(index, key)
        end
        if rule.where ~= nil and type(rule.where) ~= 'table' then
            return nil, ('invalid where in requirement %d of action %s'):format(index, key)
        end
        local where = {}
        for field, value in pairs(rule.where or {}) do
            local fieldType = observation.fields[field]
            if not fieldType then
                return nil, ('unknown field %s in requirement %d of action %s'):format(
                    tostring(field), index, key)
            end
            local numeric = fieldType == 'integer' or fieldType == 'number'
            if type(value) == 'table' then
                -- A bound on a numeric field: { gte = 500 }, { lte = 3 }, both, or
                -- { sum_gte = 2 } added up across hand-overs.
                local bounded = numeric and next(value) ~= nil
                for bound, limit in pairs(value) do
                    if (bound ~= 'gte' and bound ~= 'lte' and bound ~= 'sum_gte')
                        or type(limit) ~= 'number' or limit ~= limit then bounded = false end
                end
                if bounded and value.sum_gte and (value.gte or value.lte or value.sum_gte <= 0) then
                    bounded = false
                end
                if bounded and value.gte and value.lte and value.gte > value.lte then
                    bounded = false
                end
                if not bounded then
                    return nil, ('invalid bound on %s in requirement %d of action %s'):format(
                        field, index, key)
                end
                where[field] = { gte = value.gte, lte = value.lte, sum_gte = value.sum_gte }
            else
                local fits = (fieldType == 'string' and type(value) == 'string')
                    or (fieldType == 'boolean' and type(value) == 'boolean')
                    or (fieldType == 'integer' and math.type(value) == 'integer')
                    or (fieldType == 'number' and type(value) == 'number' and value == value)
                if not fits then
                    return nil, ('invalid value for %s in requirement %d of action %s'):format(
                        field, index, key)
                end
                where[field] = value
            end
        end
        local within = rule.within_s == nil and 600 or rule.within_s
        if math.type(within) ~= 'integer' or within < ACTION_LIMITS.withinMin
            or within > ACTION_LIMITS.withinMax then
            return nil, ('invalid within_s in requirement %d of action %s'):format(index, key)
        end
        requires[index] = {
            observation = rule.observation, where = where, within_s = within,
            consume = rule.consume == true,
        }
    end
    local limit
    if definition.limit ~= nil then
        local per, every = definition.limit.per_player, definition.limit.every_s
        if math.type(per) ~= 'integer' or per < 1 or per > 1000
            or math.type(every) ~= 'integer' or every < 1 or every > 604800 then
            return nil, ('invalid limit in action %s'):format(key)
        end
        limit = { per_player = per, every_s = every }
        if definition.limit.hint ~= nil then
            if type(definition.limit.hint) ~= 'table' or next(definition.limit.hint) == nil then
                return nil, ('invalid limit hint in action %s'):format(key)
            end
            limit.hint = {}
            for language, text in pairs(definition.limit.hint) do
                text = OBSERVATION_LANGUAGES[language] and cleanTemplate(text, ACTION_LIMITS.hint)
                if not text then return nil, ('invalid limit hint in action %s'):format(key) end
                limit.hint[language] = text
            end
        end
    end
    local usesStock
    if definition.uses_stock ~= nil then
        local item, quantity = definition.uses_stock.item, definition.uses_stock.quantity
        if quantity == nil then quantity = 1 end
        if type(item) ~= 'string' or not item:match('^[a-z0-9_.-]+$') or #item > 48
            or math.type(quantity) ~= 'integer' or quantity < 1 or quantity > 1000 then
            return nil, ('invalid uses_stock in action %s'):format(key)
        end
        usesStock = { item = item, quantity = quantity }
    end
    if definition.auto ~= nil and type(definition.auto) ~= 'boolean' then
        return nil, ('invalid auto in action %s'):format(key)
    end
    local spends = false
    for _, rule in ipairs(requires) do if rule.consume then spends = true end end
    if definition.auto == true and not spends then
        return nil, ('auto action %s needs a requirement with consume = true'):format(key)
    end
    -- Values the deed takes from the facts that unlocked it, never from the
    -- model: { amount = 'item_given.quantity' }.
    local paramsFrom = {}
    for name, source in pairs(definition.params_from or {}) do
        local observationKey, fieldName
        if type(source) == 'string' then
            observationKey, fieldName = source:match('^([a-z][a-z0-9_]*)%.([a-z][a-z0-9_]*)$')
        end
        local observation = observationKey and observations[observationKey]
        local required = false
        for _, rule in ipairs(requires) do
            if rule.observation == observationKey then required = true end
        end
        if type(name) ~= 'string' or not name:match('^[a-z][a-z0-9_]*$') or #name > 32
            or name == 'player_id' or params[name] or fixed[name]
            or not observation or not required or not observation.fields[fieldName] then
            return nil, ('invalid params_from %s in action %s'):format(tostring(name), key)
        end
        paramsFrom[name] = { observation = observationKey, field = fieldName }
    end
    local hint
    if definition.locked_hint ~= nil then
        if type(definition.locked_hint) ~= 'table' or next(definition.locked_hint) == nil then
            return nil, ('invalid locked_hint in action %s'):format(key)
        end
        hint = {}
        for language, text in pairs(definition.locked_hint) do
            text = OBSERVATION_LANGUAGES[language] and cleanTemplate(text, ACTION_LIMITS.hint)
            if not text then return nil, ('invalid locked_hint in action %s'):format(key) end
            hint[language] = text
        end
    end
    return {
        name = name, description = description, params = params, fixed = fixed,
        requires = requires, locked_hint = hint, limit = limit, uses_stock = usesStock,
        auto = definition.auto == true, params_from = paramsFrom,
    }
end

local function normalizedCustomActions(descriptor, observations)
    local actions, count = {}, 0
    for key, definition in pairs(descriptor.Actions or {}) do
        local action, err = normalizedAction(key, definition, observations)
        if not action then return nil, err end
        actions[key] = action
        count = count + 1
        if count > ACTION_LIMITS.actions then return nil, 'too many actions' end
    end
    return actions
end

local function normalizedObservations(descriptor)
    local observations, count = {}, 0
    for key, definition in pairs(descriptor.Observations or {}) do
        local observation, err = normalizedObservation(key, definition)
        if not observation then return nil, err end
        observations[key] = observation
        count = count + 1
        if count > OBSERVATION_LIMITS.observations then return nil, 'too many observations' end
    end
    return observations
end

local function normalizedActions(descriptor)
    local actions, seen = {}, {}
    for _, action in ipairs(descriptor.SupportedActions) do
        if type(action) ~= 'string' or not action:match('^[a-z][a-z0-9_]*$')
            or #action > 64 then return nil, 'invalid supported action' end
        if not seen[action] then
            actions[#actions + 1] = action
            seen[action] = true
        end
    end
    return actions
end

local function register(domain, descriptor, owner)
    domain = tostring(domain or ''):lower()
    local valid, err = validateDescriptor(domain, descriptor)
    if not valid then return false, err end

    local existing = HumalikeProviders.registered[domain][descriptor.name]
    if existing and existing.ownerResource ~= owner then
        return false, 'provider name already registered'
    end

    local provider = {}
    for key, value in pairs(descriptor) do provider[key] = value end
    if domain == 'actions' then
        provider.SupportedActions, err = normalizedActions(descriptor)
        if not provider.SupportedActions then return false, err end
        provider.Observations, err = normalizedObservations(descriptor)
        if not provider.Observations then return false, err end
        provider.Actions, err = normalizedCustomActions(descriptor, provider.Observations)
        if not provider.Actions then return false, err end
    end
    provider.ownerResource = owner
    provider.priority = descriptor.priority
    HumalikeProviders.registered[domain][provider.name] = provider
    resolve(domain)
    return true
end

local function unregister(domain, name, owner)
    domain = tostring(domain or ''):lower()
    if not DOMAINS[domain] or not validName(name) then
        return false, 'invalid provider'
    end
    local provider = HumalikeProviders.registered[domain][name]
    if not provider then return true end
    if provider.ownerResource ~= owner then return false, 'provider owned by another resource' end
    HumalikeProviders.registered[domain][name] = nil
    resolve(domain)
    return true
end

function HumalikeRegisterInternalProvider(domain, descriptor)
    return register(domain, descriptor, GetCurrentResourceName())
end

function HumalikeSelectedProvider(domain)
    return HumalikeProviders.selected[domain]
end

function HumalikeProviderCall(domain, method, ...)
    local provider = HumalikeProviders.selected[domain]
    if not provider or provider[method] == nil then return false, nil end
    local result = table.pack(pcall(provider[method], ...))
    if not result[1] then
        providerFailure(domain, provider, method, result[2])
        return false, nil
    end
    providerSuccess(domain, provider)
    return true, table.unpack(result, 2, result.n)
end

exports('RegisterProvider', function(domain, descriptor)
    local owner = GetInvokingResource()
    if not owner or owner == GetCurrentResourceName() then
        return false, 'external provider resource required'
    end
    local ok, err = register(domain, descriptor, owner)
    -- An export carries one return value across resources, so the reason a
    -- descriptor was refused would otherwise never reach its author.
    if not ok then
        print(('[humalike] %s provider from %s rejected: %s'):format(
            tostring(domain), owner, tostring(err)))
    end
    return ok, err
end)

exports('UnregisterProvider', function(domain, name)
    local owner = GetInvokingResource()
    if not owner or owner == GetCurrentResourceName() then
        return false, 'external provider resource required'
    end
    return unregister(domain, name, owner)
end)

function HumalikeGetProviderStatus()
    local status = {
        apiVersion = HumalikeProviders.apiVersion,
        runtimeEpoch = HumalikeProviders.runtimeEpoch,
        domains = {},
        selected = {},
    }
    for domain in pairs(DOMAINS) do
        local provider = HumalikeProviders.selected[domain]
        local resolution = HumalikeProviders.resolution[domain] or {}
        local selected = provider and {
            name = provider.name,
            ownerResource = provider.ownerResource,
            priority = provider.priority,
        } or false
        status.selected[domain] = selected
        status.domains[domain] = {
            setting = resolution.setting or providerSetting(domain),
            state = resolution.state or 'unresolved',
            reason = resolution.reason,
            selected = selected,
            candidates = candidateStatus(domain),
        }
    end
    return status
end

exports('GetProviderStatus', HumalikeGetProviderStatus)

AddEventHandler('onResourceStart', function(resource)
    for domain in pairs(DOMAINS) do resolve(domain) end
    if resource == GetCurrentResourceName() then
        TriggerEvent('humalike:integration:ready', {
            apiVersion = HumalikeProviders.apiVersion,
            runtimeEpoch = HumalikeProviders.runtimeEpoch,
        })
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then return end
    for domain, providers in pairs(HumalikeProviders.registered) do
        for name, provider in pairs(providers) do
            if provider.ownerResource == resource then providers[name] = nil end
        end
        resolve(domain)
    end
end)
