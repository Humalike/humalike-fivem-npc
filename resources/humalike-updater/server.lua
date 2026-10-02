-- A resource restarting itself from async code crashes FXServer
-- (citizenfx/fivem#1421), so humalike asks this one to restart it.
AddEventHandler('humalike:update:restart', function()
    local invoker = GetInvokingResource()
    if not invoker or GetResourceMetadata(invoker, 'name', 0) ~= 'humalike' then return end
    print(('[humalike-updater] restarting %s to apply its update'):format(invoker))
    SetTimeout(1000, function()
        ExecuteCommand('refresh')
        ExecuteCommand(('ensure %s'):format(invoker))
    end)
end)
