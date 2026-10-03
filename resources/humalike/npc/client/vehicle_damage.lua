local tracked

local function finite(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function sample(vehicle)
    local body = GetVehicleBodyHealth(vehicle)
    local engine = GetVehicleEngineHealth(vehicle)
    if not finite(body) or not finite(engine) then return nil end
    return body, engine
end

local function reset(vehicle, networkId, body, engine)
    tracked = {
        vehicle = vehicle,
        networkId = networkId,
        body = body,
        engine = engine,
        lastReportAt = nil,
    }
    TriggerServerEvent('humalike:npc:vehicleObserved', networkId)
end

-- On foot the seat is looked at half as often.
HumalikePulse.Every('vehicle damage', 500, function()
    local ped = HumalikePulse.Ped()
    local vehicle = ped and ped ~= 0 and DoesEntityExist(ped)
        and GetVehiclePedIsIn(ped, false) or 0
    if vehicle == 0 or not DoesEntityExist(vehicle)
        or not NetworkGetEntityIsNetworked(vehicle) then
        tracked = nil
    else
        local networkId = NetworkGetNetworkIdFromEntity(vehicle)
        local body, engine = sample(vehicle)
        if not networkId or networkId <= 0 or not body then
            tracked = nil
        elseif not tracked or tracked.vehicle ~= vehicle
            or tracked.networkId ~= networkId then
            reset(vehicle, networkId, body, engine)
        else
            tracked.body = math.max(tracked.body, body)
            tracked.engine = math.max(tracked.engine, engine)
            local bodyDrop = tracked.body - body
            local engineDrop = tracked.engine - engine
            local damage = math.max(bodyDrop, engineDrop)
            local now = GetGameTimer()
            local cooledDown = not tracked.lastReportAt
                or now < tracked.lastReportAt
                or now - tracked.lastReportAt >= Config.VehicleDamage.CooldownMs
            if cooledDown and damage >= Config.VehicleDamage.SignificantHealthDrop then
                TriggerServerEvent('humalike:npc:vehicleDamaged', networkId)
                tracked.body = body
                tracked.engine = engine
                tracked.lastReportAt = now
            end
        end
    end
    return tracked and Config.VehicleDamage.PollIntervalMs or 500
end)
