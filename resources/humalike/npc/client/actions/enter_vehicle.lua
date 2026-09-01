
NpcActions = NpcActions or {}

local MAX_DISTANCE = 12.0
local MAX_SPEED = 2.0
local attempts = {}

local function stationary(vehicle)
    return #(GetEntityVelocity(vehicle)) < MAX_SPEED
end

local function networked(vehicle)
    return DoesEntityExist(vehicle) and NetworkGetEntityIsNetworked(vehicle)
end

local function nearestVehicle(ped)
    local npcCoords = GetEntityCoords(ped)
    local best, bestDistance = nil, MAX_DISTANCE
    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if networked(vehicle) and stationary(vehicle) then
            local distance = #(GetEntityCoords(vehicle) - npcCoords)
            if distance < bestDistance
                or (distance == bestDistance and best and vehicle < best) then
                best, bestDistance = vehicle, distance
            end
        end
    end
    return best
end

local function freeSeat(ped, vehicle)
    if GetPedInVehicleSeat(vehicle, -1) ~= 0 then
        for seat = 0, 8 do
            if GetPedInVehicleSeat(vehicle, seat) == 0 then return seat end
        end
        return nil
    end
    return -1
end

NpcActions['enter_vehicle'] = function(ped, params)
    if NpcActionPedInVehicle(ped) then
        attempts[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    local partner = ActionTargetPed(ped, params, Config.Punch.MaxDistance * 4)
    local partnerVehicle = partner and GetVehiclePedIsIn(partner, false) or 0
    local vehicle = partnerVehicle ~= 0 and networked(partnerVehicle)
        and partnerVehicle or nearestVehicle(ped)
    if not vehicle then
        print('[humalike-npc] enter_vehicle: no networked vehicle within reach')
        attempts[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    local seat = freeSeat(ped, vehicle)
    if not seat then
        print('[humalike-npc] enter_vehicle: no free seat')
        attempts[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    if not NpcActionPedInVehicle(ped) then ClearPedTasks(ped) end
    MarkActionControl(ped, 'enter_vehicle')
    local attempt = { vehicle = vehicle }
    attempts[ped] = attempt
    TaskEnterVehicle(ped, vehicle, 15000, seat, 1.0, 1, 0)
    SetTimeout(20000, function()
        if attempts[ped] ~= attempt then return end
        attempts[ped] = nil
        if ActionControlledPeds[ped] == 'enter_vehicle' then ReleaseActionControl(ped) end
    end)
end
NpcActionSustain['enter_vehicle'] = function(ped)
    if NpcActionPedInVehicle(ped) then
        attempts[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    local attempt = attempts[ped]
    local vehicle = attempt and attempt.vehicle or nil
    if not vehicle or not networked(vehicle) then
        attempts[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    if GetScriptTaskStatus(ped, GetHashKey('SCRIPT_TASK_ENTER_VEHICLE')) <= 1 then return end
    local seat = freeSeat(ped, vehicle)
    if not seat then
        attempts[ped] = nil
        ReleaseActionControl(ped)
        return
    end
    TaskEnterVehicle(ped, vehicle, 15000, seat, 1.0, 1, 0)
end
