local RESOURCE = 'es_extended'

local function esx()
    return exports[RESOURCE]:getSharedObject()
end

local function player(source)
    local core = esx()
    return core and core.GetPlayerFromId(source) or nil
end

HumalikeRegisterInternalProvider('player', {
    name = 'esx',
    apiVersion = 1,
    priority = 100,

    Available = function()
        return HumalikeProviderUtils.Started(RESOURCE)
    end,

    GetCharacterId = function(source)
        local current = player(source)
        if not current then return nil end
        if HumalikeProviderUtils.Callable(current.getIdentifier) then
            return current.getIdentifier()
        end
        return current.identifier
    end,

    GetCharacterName = function(source)
        local current = player(source)
        if not current then return nil end
        if HumalikeProviderUtils.Callable(current.getName) then return current.getName() end
        return current.name
    end,

    IsCharacterLoaded = function(source)
        return player(source) ~= nil
    end,

    HasJob = function(source, names, requireDuty)
        local current = player(source)
        if not current then return false end
        local job = HumalikeProviderUtils.Callable(current.getJob)
            and current.getJob() or current.job
        return HumalikeProviderUtils.HasJob(job, names, requireDuty, false)
    end,

    Notify = function(source, message, kind)
        local current = player(source)
        if not current or not HumalikeProviderUtils.Callable(current.showNotification) then
            return false
        end
        local notifyKind = HumalikeProviderUtils.NotificationKind(kind)
        current.showNotification(message, notifyKind == 'inform' and 'info' or notifyKind)
        return true
    end,
})

HumalikeRegisterInternalProvider('inventory', {
    name = 'esx',
    apiVersion = 1,
    priority = 50,

    Available = function()
        return HumalikeProviderUtils.Started(RESOURCE)
    end,

    AddItem = function(source, itemName, quantity, metadata)
        local current = player(source)
        if not current or not HumalikeProviderUtils.Callable(current.addInventoryItem) then
            return false
        end
        if HumalikeProviderUtils.Callable(current.canCarryItem)
            and current.canCarryItem(itemName, quantity) ~= true then return false end
        current.addInventoryItem(itemName, quantity, metadata)
        return true
    end,
})
