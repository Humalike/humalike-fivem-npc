-- Restarts the humalike resource after its updater installed a release.
--
-- A FiveM resource that restarts itself from asynchronous code takes the whole
-- server down (citizenfx/fivem#1421, #1840; reproduced on FXServer with Node 22),
-- and an update is always asynchronous: it waits on a download. A restart run by
-- another resource is safe, so humalike asks this one. It writes no files and
-- answers only the resource whose manifest names itself humalike.
--
-- It needs these grants in server.cfg (ensure runs stop and start as this
-- resource):
--   add_ace resource.humalike-updater command.refresh allow
--   add_ace resource.humalike-updater command.ensure allow
--   add_ace resource.humalike-updater command.stop allow
--   add_ace resource.humalike-updater command.start allow

AddEventHandler('humalike:update:restart', function()
    local invoker = GetInvokingResource()
    if not invoker or GetResourceMetadata(invoker, 'name', 0) ~= 'humalike' then return end
    print(('[humalike-updater] restarting %s to apply its update'):format(invoker))
    SetTimeout(1000, function()
        ExecuteCommand('refresh')
        ExecuteCommand(('ensure %s'):format(invoker))
    end)
end)
