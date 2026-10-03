HumalikeWorldCabin = { epoch = nil, revision = -1, membership = nil }

local reportedVehicle = false

local function report(sample, force)
    local vehicle = type(sample) == 'table' and sample.vehicle or nil
    local digest = vehicle and ('%s:%s'):format(vehicle.networkId, vehicle.seat) or ''
    if not force and digest == reportedVehicle then return end
    reportedVehicle = digest
    TriggerServerEvent('humalike:world:cabinState', vehicle)
end

HumalikeWorldCollector.Subscribe('motion', function(sample)
    report(sample, false)
end)

RegisterNetEvent('humalike:world:requestCabinState', function()
    report(HumalikeWorldCollector and HumalikeWorldCollector.latest, true)
end)

RegisterNetEvent('humalike:world:cabinMembership', function(snapshot)
    if type(snapshot) ~= 'table' or type(snapshot.epoch) ~= 'string'
        or type(snapshot.revision) ~= 'number' then return end
    if HumalikeWorldCabin.epoch ~= snapshot.epoch then
        HumalikeWorldCabin.epoch = snapshot.epoch
        HumalikeWorldCabin.revision = -1
    end
    if snapshot.revision < HumalikeWorldCabin.revision then return end
    HumalikeWorldCabin.revision = snapshot.revision
    HumalikeWorldCabin.membership = type(snapshot.membership) == 'table'
        and HumalikeWorldContracts.Copy(snapshot.membership) or nil
end)
