local RESOURCE = 'qb-core'
local original
local definition
local wrapped

local function actionText(args)
    if type(args) ~= 'table' or #args == 0 then return nil end
    for index = 1, #args do
        if type(args[index]) ~= 'string' then return nil end
    end
    return table.concat(args, ' '):gsub('[~<].-[>~]', '')
end

local function core()
    if GetResourceState(RESOURCE) ~= 'started' then return nil end
    local ok, framework = pcall(function()
        return exports[RESOURCE]:GetCoreObject({ 'Commands' })
    end)
    return ok and framework or nil
end

local function restore()
    local framework = core()
    local current = framework and framework.Commands and framework.Commands.List
        and framework.Commands.List.me
    if not original or not definition or not current or current.callback ~= wrapped then return end
    framework.Commands.Add('me', definition.help, definition.arguments,
        definition.argsrequired, original, definition.permission)
    original = nil
    definition = nil
    wrapped = nil
end

local function install()
    if original or HumalikePlayer.Name() ~= 'qbcore' then return end
    local framework = core()
    local commands = framework and framework.Commands
    local list = commands and commands.List
    local command = list and list.me
    if not command or not HumalikeProviderUtils.Callable(command.callback)
        or not HumalikeProviderUtils.Callable(commands.Add) then
        return
    end

    original = command.callback
    definition = {
        help = command.help,
        arguments = command.arguments,
        argsrequired = command.argsrequired,
        permission = command.permission,
    }
    wrapped = function(playerId, args, rawCommand)
        original(playerId, args, rawCommand)
        if HumalikePlayer.Name() ~= 'qbcore' then return end
        local text = actionText(args)
        if not text then return end
        HumalikeReportPlayerEvent(playerId, { type = 'rp_action', kind = 'me', text = text })
    end

    framework.Commands.Add('me', definition.help, definition.arguments,
        definition.argsrequired, wrapped, definition.permission)
end

SetTimeout(0, install)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end
    original = nil
    definition = nil
    wrapped = nil
    SetTimeout(0, install)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        restore()
    elseif resourceName == RESOURCE then
        original = nil
        definition = nil
        wrapped = nil
    end
end)
