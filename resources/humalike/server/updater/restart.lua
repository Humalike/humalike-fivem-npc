-- Restarts humalike after the updater (updater.js) installed a release.
-- Running `ensure` from the updater's own JavaScript takes the whole FXServer
-- process down (measured on FXServer with Node 22: "Server process close
-- detected" a second later, every time), so the JavaScript only asks and this
-- main-thread Lua script runs the commands a moment later.
local resourceName = GetCurrentResourceName()

AddEventHandler('humalike:update:restart', function()
    local invoker = GetInvokingResource()
    if invoker and invoker ~= resourceName then return end
    SetTimeout(1000, function()
        ExecuteCommand('refresh')
        ExecuteCommand(('ensure %s'):format(resourceName))
    end)
end)
