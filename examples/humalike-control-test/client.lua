local visible, sequence = false, 0
local pending = {}

local function close()
    visible = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end

local function request(operation, npcId, callback)
    sequence = sequence % 2147483647 + 1
    local id = sequence
    pending[id] = callback
    TriggerServerEvent('humalike-control-test:request', id, operation, npcId)
    SetTimeout(8000, function()
        if not pending[id] then return end
        local reply = pending[id]
        pending[id] = nil
        reply({ ok = false, message = 'Server request timed out' })
    end)
end

local function open(rows)
    visible = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open', rows = rows })
end

RegisterNetEvent('humalike-control-test:open', open)
RegisterNetEvent('humalike-control-test:response', function(id, response)
    local callback = pending[id]
    if not callback then return end
    pending[id] = nil
    callback(response)
end)
RegisterNUICallback('close', function(_, callback) close(); callback({ ok = true }) end)
RegisterNUICallback('request', function(data, callback)
    if not visible or type(data) ~= 'table' then callback({ ok = false }); return end
    request(data.operation, data.npcId, callback)
end)
RegisterCommand('humalike_npc_test_panel', function()
    if visible then close(); return end
    request('refresh', nil, function(response)
        if response.ok then open(response.rows)
        else TriggerEvent('chat:addMessage', { args = { 'HumaLike test', response.message } }) end
    end)
end, false)
RegisterKeyMapping('humalike_npc_test_panel', 'HumaLike external NPC test panel', 'keyboard', 'F7')
AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then close() end
end)
