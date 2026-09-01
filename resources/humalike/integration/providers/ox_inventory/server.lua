local RESOURCE = 'ox_inventory'

HumalikeRegisterInternalProvider('inventory', {
    name = RESOURCE,
    apiVersion = 1,
    priority = 100,

    Available = function()
        return HumalikeProviderUtils.Started(RESOURCE)
    end,

    AddItem = function(source, itemName, quantity, metadata)
        local success = exports[RESOURCE]:AddItem(source, itemName, quantity, metadata)
        return success == true
    end,
})
