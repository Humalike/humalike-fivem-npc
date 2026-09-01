local function registerInteractionProvider()
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == GetCurrentResourceName() then registerInteractionProvider() end
end)

AddEventHandler('humalike:integration:ready', registerInteractionProvider)
