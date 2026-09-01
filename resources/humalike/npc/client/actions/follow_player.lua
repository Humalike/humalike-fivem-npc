NpcActions = NpcActions or {}

local taskedGait = {}
local vehicleStates = {}

local function nowMs()
    return GetGameTimer()
end

local function taskFollow(ped, target, gait)
    TaskFollowToOffsetOfEntity(ped, target,
        0.0, Config.Follow.OffsetBehind, 0.0,
        gait, -1, Config.Follow.StoppingRange, true)
end

local function desiredGait(ped, target)
    local gap = #(GetEntityCoords(ped) - GetEntityCoords(target))
    if gap > Config.Follow.SprintBehindDistance then return 3.0 end
    if gap > Config.Follow.RunBehindDistance then return 2.0 end
    local speed = GetEntitySpeed(target)
    if speed > Config.Follow.SprintSpeedThreshold then return 3.0 end
    if speed > Config.Follow.RunSpeedThreshold then return 2.0 end
    return 1.0
end

local function partnerPed(ped)
    local params = ActionParams[ped]
    local serverId = params and params.player_id
    if type(serverId) ~= 'number' then return nil end
    local playerId = GetPlayerFromServerId(serverId)
    if playerId == -1 then return nil end
    local target = GetPlayerPed(playerId)
    if target == 0 or not DoesEntityExist(target) then return nil end
    return target
end

local function actionParams(ped, vehicle, seat)
    local current = ActionParams[ped] or {}
    local params = { player_id = current.player_id }
    if vehicle and vehicle ~= 0 and seat ~= nil then
        local networkId = NetworkGetNetworkIdFromEntity(vehicle)
        if networkId and networkId > 0 then
            params.vehicle_network_id = networkId
            params.passenger_seat = seat
        end
    end
    return params
end
local function updateReservation(ped, vehicle, seat)
    local params = actionParams(ped, vehicle, seat)
    local current = ActionParams[ped] or {}
    if current.player_id == params.player_id
        and current.vehicle_network_id == params.vehicle_network_id
        and current.passenger_seat == params.passenger_seat then return end
    MarkActionControl(ped, 'follow_player', params)
end

local function seatReservedByAnother(ped, vehicleNetworkId, seat)
    for other, actionKey in pairs(ActionControlledPeds) do
        if other ~= ped and actionKey == 'follow_player' and DoesEntityExist(other) then
            local params = ActionParams[other]
            if params and params.vehicle_network_id == vehicleNetworkId
                and params.passenger_seat == seat then return true end
        end
    end
    return false
end

local function freePassengerSeat(ped, vehicle)
    local networkId = NetworkGetNetworkIdFromEntity(vehicle)
    if not networkId or networkId <= 0 then return nil end
    local maxPassengers = GetVehicleMaxNumberOfPassengers(vehicle)
    if maxPassengers <= 0 then return nil end
    local pedNetworkId = NetworkGetNetworkIdFromEntity(ped)
    local start = pedNetworkId and pedNetworkId > 0 and pedNetworkId % maxPassengers or 0
    for offset = 0, maxPassengers - 1 do
        local seat = (start + offset) % maxPassengers
        if IsVehicleSeatFree(vehicle, seat, true)
            and not seatReservedByAnother(ped, networkId, seat) then return seat end
    end
    return nil
end

local function vehicleUnlocked(vehicle)
    local lockStatus = GetVehicleDoorLockStatus(vehicle)
    return lockStatus == 0 or lockStatus == 1
end

local function resetVehicleState(ped)
    vehicleStates[ped] = nil
end

local function leaveTaskActive(ped)
    return GetScriptTaskStatus(ped, GetHashKey('SCRIPT_TASK_LEAVE_VEHICLE')) <= 1
end

local function leaveStillFinishing(ped, state)
    if not state or state.mode ~= 'leaving' and state.mode ~= 'stopping' then return false end
    local now = nowMs()
    local withinTimeout = now < state.taskIssuedAt
        or now - state.taskIssuedAt < Config.Follow.VehicleTaskTimeoutMs
    return withinTimeout and leaveTaskActive(ped)
end

local function issueLeave(ped, vehicle, stopping)
    vehicleStates[ped] = {
        mode = stopping and 'stopping' or 'leaving',
        vehicle = vehicle,
        taskIssuedAt = nowMs(),
    }
    TaskLeaveVehicle(ped, vehicle, 0)
end

local function leaveIfNeeded(ped, vehicle, stopping)
    local state = vehicleStates[ped]
    if state and state.mode == (stopping and 'stopping' or 'leaving')
        and state.vehicle == vehicle
        and nowMs() - state.taskIssuedAt < Config.Follow.VehicleTaskTimeoutMs then return true end
    issueLeave(ped, vehicle, stopping)
    return true
end

local function sustainOnFoot(ped, target)
    updateReservation(ped)
    vehicleStates[ped] = { mode = 'foot' }
    local wanted = desiredGait(ped, target)
    local dropped = GetScriptTaskStatus(
        ped, GetHashKey('SCRIPT_TASK_FOLLOW_TO_OFFSET_OF_ENTITY')) > 1
    if wanted ~= taskedGait[ped] or dropped then
        taskedGait[ped] = wanted
        taskFollow(ped, target, wanted)
    end
end
local function sustainVehicleFollow(ped, target)
    local targetVehicle = GetVehiclePedIsIn(target, false)
    local pedVehicle = GetVehiclePedIsIn(ped, false)

    if pedVehicle ~= 0 then
        if targetVehicle ~= 0 and pedVehicle == targetVehicle then
            vehicleStates[ped] = { mode = 'riding', vehicle = pedVehicle }
            return
        end
        updateReservation(ped)
        leaveIfNeeded(ped, pedVehicle, false)
        return
    end

    local state = vehicleStates[ped]
    if leaveStillFinishing(ped, state) then return end
    if not state and leaveTaskActive(ped) then
        vehicleStates[ped] = { mode = 'leaving', vehicle = 0, taskIssuedAt = nowMs() }
        return
    end
    if state and (state.mode == 'leaving' or state.mode == 'stopping') then
        vehicleStates[ped] = nil
    end
    if targetVehicle == 0 then
        sustainOnFoot(ped, target)
        return
    end

    local now = nowMs()
    if state and state.mode == 'entering' and state.vehicle == targetVehicle then
        if now - state.taskIssuedAt < Config.Follow.VehicleTaskTimeoutMs then return end
        updateReservation(ped)
        vehicleStates[ped] = { mode = 'waiting', retryAt = now + Config.Follow.VehicleRetryMs }
        return
    end
    if state and state.mode == 'waiting' and now < state.retryAt then return end
    if not vehicleUnlocked(targetVehicle) then
        updateReservation(ped)
        vehicleStates[ped] = { mode = 'waiting', retryAt = now + Config.Follow.VehicleRetryMs }
        return
    end

    local seat = freePassengerSeat(ped, targetVehicle)
    if seat == nil then
        updateReservation(ped)
        vehicleStates[ped] = { mode = 'waiting', retryAt = now + Config.Follow.VehicleRetryMs }
        return
    end

    updateReservation(ped, targetVehicle, seat)
    taskedGait[ped] = nil
    vehicleStates[ped] = {
        mode = 'entering',
        vehicle = targetVehicle,
        seat = seat,
        taskIssuedAt = now,
    }
    TaskEnterVehicle(ped, targetVehicle, Config.Follow.VehicleTaskTimeoutMs,
        seat, Config.Follow.VehicleEntrySpeed, 1, 0)
end

local function forgetStaleState()
    for ped in pairs(taskedGait) do
        if ActionControlledPeds[ped] ~= 'follow_player' then taskedGait[ped] = nil end
    end
    for ped in pairs(vehicleStates) do
        local action = ActionControlledPeds[ped]
        if action ~= 'follow_player' and action ~= 'stop_following' then
            vehicleStates[ped] = nil
        end
    end
end

NpcActions['follow_player'] = function(ped, params)
    local target = ActionTargetPed(ped, params, Config.Follow.MaxDistance)
    if not target then
        print('[humalike-npc] follow_player: nobody within reach')
        return
    end
    local serverId = params and params.player_id
    if type(serverId) ~= 'number' then
        serverId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(target))
    end
    local seated = NpcActionPedInVehicle(ped)
    ReleaseActionControl(ped)
    if not seated then ClearPedTasks(ped) end
    MarkActionControl(ped, 'follow_player', { player_id = serverId })
    taskedGait[ped] = nil
    resetVehicleState(ped)
    sustainVehicleFollow(ped, target)
end

NpcActionSustain['follow_player'] = function(ped)
    forgetStaleState()
    local target = partnerPed(ped)
    if not target then
        BeginStopFollowing(ped)
        return
    end
    sustainVehicleFollow(ped, target)
end
function BeginStopFollowing(ped)
    taskedGait[ped] = nil
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        MarkActionControl(ped, 'stop_following', {})
        issueLeave(ped, vehicle, true)
        return
    end

    local state = vehicleStates[ped]
    if leaveStillFinishing(ped, state) then
        state.mode = 'stopping'
        MarkActionControl(ped, 'stop_following', {})
        return
    end
    if not state and leaveTaskActive(ped) then
        vehicleStates[ped] = { mode = 'stopping', vehicle = 0, taskIssuedAt = nowMs() }
        MarkActionControl(ped, 'stop_following', {})
        return
    end

    resetVehicleState(ped)
    ClearPedTasks(ped)
    ReleaseActionControl(ped)
end

NpcActionSustain['stop_following'] = function(ped)
    forgetStaleState()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        leaveIfNeeded(ped, vehicle, true)
        return
    end

    local state = vehicleStates[ped]
    if leaveStillFinishing(ped, state) then return end
    if not state and leaveTaskActive(ped) then
        vehicleStates[ped] = { mode = 'stopping', vehicle = 0, taskIssuedAt = nowMs() }
        return
    end
    resetVehicleState(ped)
    ClearPedTasks(ped)
    ReleaseActionControl(ped)
end
