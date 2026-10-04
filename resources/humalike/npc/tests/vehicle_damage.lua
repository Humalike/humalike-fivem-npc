Config = {
    VehicleDamage = {
        PollIntervalMs = 250,
        SignificantHealthDrop = 50,
        SevereHealthDrop = 200,
        SevereEngineHealth = 300,
        CooldownMs = 10000,
    },
}

local sent = {}
local ped, vehicle = 1, 20
local pedVehicle, networked = 0, true
local bodyHealth, engineHealth, timer = 1000.0, 1000.0, 0
local pulseAt = 0

function CreateThread() end
function PlayerPedId() return ped end
function DoesEntityExist(entity) return entity == ped or entity == vehicle or entity == 21 end
function GetVehiclePedIsIn() return pedVehicle end
function NetworkGetEntityIsNetworked() return networked end
function NetworkGetNetworkIdFromEntity(entity) return entity == vehicle and 120 or 121 end
function GetVehicleBodyHealth() return bodyHealth end
function GetVehicleEngineHealth() return engineHealth end
function GetGameTimer() return timer end
function TriggerServerEvent(...) sent[#sent + 1] = { ... } end

local function tick()
    pulseAt = pulseAt + 500
    local sleep = HumalikePulse.Run(pulseAt)
    local tracking = pedVehicle ~= 0 and networked
    assert(sleep == (tracking and 250 or 500), ('next poll in %s'):format(tostring(sleep)))
end

dofile('../world/client/pulse.lua')
dofile('client/vehicle_damage.lua')

tick() -- on foot
pedVehicle = vehicle
tick() -- establishes and announces the baseline
assert(#sent == 1 and sent[1][1] == 'humalike:npc:vehicleObserved')
assert(sent[1][2] == 120 and sent[1][3] == nil)
bodyHealth = 970
tick()
assert(#sent == 1, 'minor scrapes are ignored')
bodyHealth = 940
tick()
assert(#sent == 2)
assert(sent[2][1] == 'humalike:npc:vehicleDamaged')
assert(sent[2][2] == 120 and sent[2][3] == nil)
engineHealth = 250
timer = 9999
tick()
assert(#sent == 2)
timer = 10000
tick()
assert(#sent == 3 and sent[3][1] == 'humalike:npc:vehicleDamaged'
    and sent[3][2] == 120 and sent[3][3] == nil)
pedVehicle = 21
bodyHealth, engineHealth = 500, 250
timer = 20000
tick()
assert(#sent == 4 and sent[4][1] == 'humalike:npc:vehicleObserved'
    and sent[4][2] == 121)
bodyHealth = 440
tick()
assert(#sent == 5 and sent[5][1] == 'humalike:npc:vehicleDamaged'
    and sent[5][2] == 121 and sent[5][3] == nil)
pedVehicle = 0
tick()
pedVehicle = vehicle
bodyHealth, engineHealth = 100, 100
networked = false
tick()
networked = true
tick()
assert(#sent == 6 and sent[6][1] == 'humalike:npc:vehicleObserved')

print('vehicle_damage client: ok')
