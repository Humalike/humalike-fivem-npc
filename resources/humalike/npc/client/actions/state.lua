ActionControlledPeds = {}
ActionParams = {}
NpcActionSustain = {}
function NpcActionPedInVehicle(ped)
    return GetVehiclePedIsIn(ped, false) ~= 0
end
local function nearestPlayerPedWithin(ped, maxDistance)
    local npcCoords = GetEntityCoords(ped)
    local best, bestDistance = nil, maxDistance
    for _, playerId in ipairs(GetActivePlayers()) do
        local playerPed = GetPlayerPed(playerId)
        if playerPed ~= 0 and DoesEntityExist(playerPed) then
            local distance = #(GetEntityCoords(playerPed) - npcCoords)
            if distance < bestDistance then
                best, bestDistance = playerPed, distance
            end
        end
    end
    return best
end
function ActionTargetPed(ped, params, maxDistance)
    local serverId = params and params.player_id
    if type(serverId) == 'number' then
        local playerId = GetPlayerFromServerId(serverId)
        if playerId ~= -1 then
            local targetPed = GetPlayerPed(playerId)
            if targetPed ~= 0 and DoesEntityExist(targetPed)
                and #(GetEntityCoords(targetPed) - GetEntityCoords(ped)) < maxDistance then
                return targetPed
            end
        end
        return nil
    end
    return nearestPlayerPedWithin(ped, maxDistance)
end

function MarkActionControl(ped, actionKey, params)
    ActionControlledPeds[ped] = actionKey or true
    ActionParams[ped] = params
    if DoesEntityExist(ped) then
        if type(actionKey) == 'string' and NpcActionSustain[actionKey] ~= nil then
            -- Replicate sustained actions across OneSync ownership migration.
            Entity(ped).state:set('humalike_action', { key = actionKey, params = params }, true)
        else
            Entity(ped).state:set('humalike_action', nil, true)
        end
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetPedKeepTask(ped, true)
    end
end

function ReleaseActionControl(ped)
    ActionControlledPeds[ped] = nil
    ActionParams[ped] = nil
    if DoesEntityExist(ped) then
        Entity(ped).state:set('humalike_action', nil, true)
        SetPedKeepTask(ped, false)
        SetBlockingOfNonTemporaryEvents(ped, false)
    end
end
AddStateBagChangeHandler('humalike_action', nil, function(bagName, _key, value)
    local ped = GetEntityFromStateBagName(bagName)
    if ped == 0 or not DoesEntityExist(ped) or IsPedAPlayer(ped) then return end
    if type(value) == 'table' and type(value.key) == 'string' then
        ActionControlledPeds[ped] = value.key
        ActionParams[ped] = type(value.params) == 'table' and value.params or nil
    elseif value == nil then
        local current = ActionControlledPeds[ped]
        if current and NpcActionSustain[current] ~= nil then
            ActionControlledPeds[ped] = nil
            ActionParams[ped] = nil
            SetPedKeepTask(ped, false)
            SetBlockingOfNonTemporaryEvents(ped, false)
        end
    end
end)
function DownedNpcOf(ped)
    local npcId = DoesEntityExist(ped) and Entity(ped).state.humalike_npc_id or nil
    if not npcId then return nil end
    return HumalikeDownedState(npcId)
end

function IsActionControlled(ped)
    return ActionControlledPeds[ped] ~= nil
end

CreateThread(function()
    while true do
        Wait(Config.ActionSustainTickMs)
        for ped, actionKey in pairs(ActionControlledPeds) do
            if not DoesEntityExist(ped) then
                ActionControlledPeds[ped] = nil
                ActionParams[ped] = nil
            elseif HumalikeDownedState and DownedNpcOf(ped) then
                ReleaseActionControl(ped)
            elseif NetworkHasControlOfEntity(ped)
                and not IsEntityDead(ped) and not IsPedRagdoll(ped) then
                SetBlockingOfNonTemporaryEvents(ped, true)
                SetPedKeepTask(ped, true)
                local sustain = NpcActionSustain[actionKey]
                if sustain then sustain(ped) end
            end
        end
    end
end)
