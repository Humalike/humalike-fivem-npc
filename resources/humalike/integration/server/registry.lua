
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
    actions = { required = { 'RunAction' } },
}

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
    if domain == 'actions' and type(descriptor.SupportedActions) ~= 'table' then
        return false, 'missing SupportedActions'
    end
    return true
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
    return register(domain, descriptor, owner)
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
