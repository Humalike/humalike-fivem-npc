local RESOURCE = 'qb-inventory'

HumalikeRegisterInternalProvider('inventory', {
    name = 'qb_inventory',
    apiVersion = 1,
    priority = 100,

    Available = function()
        return HumalikeProviderUtils.Started(RESOURCE)
    end,

    AddItem = function(source, itemName, quantity, metadata)
        return exports[RESOURCE]:AddItem(
            source, itemName, quantity, false, metadata, 'humalike') == true
    end,
})
