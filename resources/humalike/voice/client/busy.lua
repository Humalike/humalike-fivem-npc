-- Reasons the player's voice is busy elsewhere (a radio, a phone call), so
-- HumaLike's push to talk stays off. Built-in adapters watch known voice
-- resources; any resource reports its own through the SetVoiceBusy export.
HumalikeVoiceBusy = { reasons = {}, listeners = {} }

local function validReason(reason)
    return type(reason) == 'string' and reason:match('^[%w_.:-]+$') ~= nil and #reason <= 64
end

function HumalikeVoiceBusy.Active()
    return next(HumalikeVoiceBusy.reasons) ~= nil
end

function HumalikeVoiceBusy.Reasons()
    local list = {}
    for reason in pairs(HumalikeVoiceBusy.reasons) do list[#list + 1] = reason end
    table.sort(list)
    return list
end

function HumalikeVoiceBusy.Has(suffix)
    for reason in pairs(HumalikeVoiceBusy.reasons) do
        if reason:sub(-#suffix) == suffix then return true end
    end
    return false
end

function HumalikeVoiceBusy.Set(reason, active)
    if not validReason(reason) then return false end
    local was = HumalikeVoiceBusy.Active()
    HumalikeVoiceBusy.reasons[reason] = active == true or nil
    local now = HumalikeVoiceBusy.Active()
    if was ~= now then
        for _, listener in ipairs(HumalikeVoiceBusy.listeners) do listener(now) end
    end
    return true
end

function HumalikeVoiceBusy.Subscribe(listener)
    HumalikeVoiceBusy.listeners[#HumalikeVoiceBusy.listeners + 1] = listener
end

function HumalikeVoiceBusy.ClearPrefix(prefix)
    for reason in pairs(HumalikeVoiceBusy.reasons) do
        if reason:sub(1, #prefix) == prefix then HumalikeVoiceBusy.Set(reason, false) end
    end
end

-- Another resource's reasons carry its name and are dropped when it stops.
exports('SetVoiceBusy', function(reason, active)
    local owner = GetInvokingResource()
    if not owner or not validReason(reason) then return false end
    return HumalikeVoiceBusy.Set(owner .. ':' .. reason, active == true)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then return end
    HumalikeVoiceBusy.ClearPrefix(resourceName .. ':')
end)
