HumalikeProviderUtils = {}

function HumalikeProviderUtils.Started(resource)
    return GetResourceState(resource) == 'started'
end

function HumalikeProviderUtils.Callable(value)
    return type(value) == 'function' or type(value) == 'table'
end

function HumalikeProviderUtils.CharacterName(data)
    local charinfo = data and data.charinfo or nil
    if type(charinfo) ~= 'table' then return nil end
    local first = type(charinfo.firstname) == 'string' and charinfo.firstname or ''
    local last = type(charinfo.lastname) == 'string' and charinfo.lastname or ''
    local name = (first .. ' ' .. last):match('^%s*(.-)%s*$')
    return name ~= '' and name or nil
end

function HumalikeProviderUtils.HasJob(job, names, requireDuty, strictDuty)
    if type(job) ~= 'table' or type(job.name) ~= 'string' then return false end
    local matches = false
    for _, name in ipairs(names) do
        if job.name == name then
            matches = true
            break
        end
    end
    if not matches or not requireDuty then return matches end
    local duty = job.onduty
    if duty == nil then duty = job.onDuty end
    if duty == nil then return strictDuty ~= true end
    return duty == true
end

function HumalikeProviderUtils.NotificationKind(kind)
    if kind == 'success' or kind == 'error' or kind == 'warning' then return kind end
    return 'inform'
end
