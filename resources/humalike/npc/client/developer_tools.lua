
local initialized = {}

local function addCommandSuggestion()
    TriggerEvent('chat:addSuggestion', '/humalike_dev', 'HumaLike ambient NPC developer tools', {
        { name = 'ambient', help = 'Ambient NPC tools' },
        { name = 'spawn|goto|remove|list', help = 'Operation to perform' },
        { name = 'npc_uuid', help = 'Canonical NPC UUID (not required for list)' },
    })
end

addCommandSuggestion()

RegisterNetEvent('humalike:npc:developerReply')
AddEventHandler('humalike:npc:developerReply', function(message)
    if type(message) == 'string' and message ~= '' then print(message) end
end)

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == 'chat' then addCommandSuggestion() end
end)

AddEventHandler('humalike:npc:ambientPedAssigned', function(_, ped)
    CreateThread(function()
        local deadline = GetGameTimer() + 5000
        while DoesEntityExist(ped) and GetGameTimer() < deadline do
            local spawnId = Entity(ped).state.humalike_debug_spawn_id
            if type(spawnId) == 'string' and initialized[ped] ~= spawnId
                and NetworkHasControlOfEntity(ped) then
                initialized[ped] = spawnId
                SetPedKeepTask(ped, true)
                TaskWanderStandard(ped, 10.0, 10)
                return
            end
            Wait(100)
        end
    end)
end)

AddEventHandler('humalike:npc:ambientPedRemoved', function(_, ped)
    initialized[ped] = nil
end)

RegisterNetEvent('humalike:npc:developerGotoAmbient')
AddEventHandler('humalike:npc:developerGotoAmbient', function(networkId)
    if type(networkId) ~= 'number' or networkId <= 0 then return end
    local deadline = GetGameTimer() + 5000
    while not NetworkDoesEntityExistWithNetworkId(networkId) and GetGameTimer() < deadline do
        Wait(50)
    end
    if not NetworkDoesEntityExistWithNetworkId(networkId) then return end
    local ped = NetworkGetEntityFromNetworkId(networkId)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return end
    local destination = GetOffsetFromEntityInWorldCoords(ped, 1.5, -1.5, 0.0)
    RequestCollisionAtCoord(destination.x, destination.y, destination.z)
    SetEntityCoordsNoOffset(PlayerPedId(), destination.x, destination.y, destination.z,
        false, false, false)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        initialized = {}
        TriggerEvent('chat:removeSuggestion', '/humalike_dev')
    end
end)
