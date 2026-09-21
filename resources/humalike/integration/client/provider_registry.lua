-- Client provider selection shared by the interaction and audio hub domains:
-- one registry per domain, same convar grammar, priority rules and failure
-- accounting.

HumalikeProviderRegistry = {}

local registries = {}

function HumalikeProviderRegistry.callable(value)
    return type(value) == 'function' or type(value) == 'table'
end

function HumalikeProviderRegistry.validName(value)
    return type(value) == 'string' and value:match('^[%w_.-]+$') ~= nil
        and value == value:lower() and value ~= 'none' and #value <= 64
end

---options = { domain, label, noun, adapters }: `domain` is the
---Config.Integrations key and status line prefix, `label` the print prefix for
---callback failures, `noun` the word used in resolution reasons.
function HumalikeProviderRegistry.new(options)
    local registry = {
        adapters = options.adapters,
        selectedName = nil,
        resolution = { state = 'unresolved' },
    }

    function registry.setting()
        return tostring((Config.Integrations or {})[options.domain] or 'auto'):lower()
    end

    function registry.available(adapter)
        if adapter.Available == nil then return true end
        local ok, result = pcall(adapter.Available)
        return ok and result == true
    end

    function registry.reportFailure(adapter, method, message)
        local now = GetGameTimer()
        local failure = adapter.failure or { count = 0, suppressed = 0 }
        failure.count = failure.count + 1
        failure.method = method
        failure.message = tostring(message)
        failure.at = now
        if not failure.reportedAt or now - failure.reportedAt >= 10000 then
            local suffix = failure.suppressed > 0
                and (' (%d suppressed)'):format(failure.suppressed) or ''
            print(('[humalike] %s %s.%s failed: %s%s'):format(
                options.label, adapter.name, method, failure.message, suffix))
            failure.reportedAt = now
            failure.suppressed = 0
        else
            failure.suppressed = failure.suppressed + 1
        end
        adapter.failure = failure
        if registry.selectedName == adapter.name then
            registry.resolution.state = 'degraded'
            registry.resolution.reason = ('%s callback failed'):format(method)
        end
    end

    function registry.call(adapter, method, ...)
        if not adapter or not HumalikeProviderRegistry.callable(adapter[method]) then
            return false, nil
        end
        local result = table.pack(pcall(adapter[method], ...))
        if not result[1] then
            registry.reportFailure(adapter, method, result[2])
            return false, nil
        end
        adapter.failure = nil
        if registry.selectedName == adapter.name then
            registry.resolution.state = 'selected'
            registry.resolution.reason = nil
        end
        return true, table.unpack(result, 2, result.n)
    end

    function registry.resolve()
        local forced = registry.setting()
        local eligible, highestPriority = {}, nil
        for name, adapter in pairs(registry.adapters) do
            adapter.name = name
            local priority = tonumber(adapter.priority) or 0
            if (forced == 'auto' or forced == name) and registry.available(adapter) then
                if forced ~= 'auto' then
                    eligible = { adapter }
                    break
                elseif highestPriority == nil or priority > highestPriority then
                    highestPriority = priority
                    eligible = { adapter }
                elseif priority == highestPriority then
                    eligible[#eligible + 1] = adapter
                end
            end
        end
        local selected
        if #eligible == 1 then
            selected = eligible[1]
            registry.resolution = { state = selected.failure and 'degraded' or 'selected' }
        elseif #eligible > 1 then
            registry.resolution = { state = 'ambiguous',
                reason = ('multiple %ss share the highest priority'):format(options.noun) }
        elseif forced == 'none' then
            registry.resolution = { state = 'disabled' }
        else
            registry.resolution = { state = 'unavailable',
                reason = ('no available %s'):format(options.noun) }
        end
        registry.selectedName = selected and selected.name or nil
        return selected
    end

    ---Validates the descriptor fields every domain shares; `methods` lists the
    ---required callbacks and `optional` the callable-if-present ones.
    function registry.validDescriptor(descriptor, methods, optional)
        if type(descriptor) ~= 'table'
            or not HumalikeProviderRegistry.validName(descriptor.name)
            or type(descriptor.priority) ~= 'number'
            or descriptor.priority ~= descriptor.priority
            or math.abs(descriptor.priority) > 100000
            or descriptor.Available ~= nil
            and not HumalikeProviderRegistry.callable(descriptor.Available) then
            return false
        end
        for _, method in ipairs(methods) do
            if not HumalikeProviderRegistry.callable(descriptor[method]) then return false end
        end
        for _, method in ipairs(optional or {}) do
            if descriptor[method] ~= nil
                and not HumalikeProviderRegistry.callable(descriptor[method]) then
                return false
            end
        end
        return true
    end

    function registry.status()
        registry.resolve()
        local selected = registry.selectedName
            and registry.adapters[registry.selectedName] or nil
        return {
            setting = registry.setting(),
            state = registry.resolution.state,
            reason = registry.resolution.reason,
            selected = selected and {
                name = selected.name,
                ownerResource = selected.ownerResource,
                priority = selected.priority,
            } or false,
        }
    end

    function registry.statusLine()
        local status = registry.status()
        return ('[humalike] %s setting=%s state=%s selected=%s%s%s'):format(
            options.domain,
            status.setting,
            status.state,
            status.selected and status.selected.name or 'none',
            status.reason and (' reason=%s'):format(status.reason) or '',
            options.extra and options.extra() or '')
    end

    registries[#registries + 1] = registry
    return registry
end

if type(RegisterCommand) == 'function' then
    RegisterCommand('humalike_status', function()
        for _, registry in ipairs(registries) do print(registry.statusLine()) end
    end, false)
end
