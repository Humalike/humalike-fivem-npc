HumalikeInventory = {}

function HumalikeInventory.Available()
    return HumalikeSelectedProvider('inventory') ~= nil
end

function HumalikeInventory.AddItem(source, itemName, quantity, metadata)
    local ok, value = HumalikeProviderCall(
        'inventory', 'AddItem', source, itemName, quantity, metadata)
    return ok and value == true
end
