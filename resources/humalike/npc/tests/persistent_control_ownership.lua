local threads = {}
local calls = {}
local waits = 0

LoadedPeds = { ['external-1'] = 101, ['static-1'] = 202 }
KnownNpcs = {
    ['external-1'] = {
        npc_id = 'external-1', type = 'external', x = 1.0, y = 2.0, z = 3.0, heading = 4.0,
    },
    ['static-1'] = {
        npc_id = 'static-1', type = 'static', x = 5.0, y = 6.0, z = 7.0, heading = 8.0,
    },
}

function CreateThread(callback) threads[#threads + 1] = callback end
function AddEventHandler() end
function Wait()
    waits = waits + 1
    if waits > 1 then error('done') end
end
function DoesEntityExist() return true end
function NetworkGetNetworkIdFromEntity(ped) return ped + 10 end
function NetworkHasControlOfEntity() return true end
function Entity() return { state = { humalike_runtime_token = 'token' } } end
function IsPedFleeing() return false end
function SetEntityCoordsNoOffset(ped) calls[#calls + 1] = { 'coords', ped } end
function SetEntityHeading(ped) calls[#calls + 1] = { 'heading', ped } end
function FreezeEntityPosition(ped) calls[#calls + 1] = { 'freeze', ped } end
function SetEntityInvincible(ped) calls[#calls + 1] = { 'invincible', ped } end
function SetEntityCanBeDamaged(ped) calls[#calls + 1] = { 'damage', ped } end
function SetEntityMaxHealth(ped) calls[#calls + 1] = { 'max-health', ped } end
function GetEntityMaxHealth() return 1000000 end
function SetEntityHealth(ped) calls[#calls + 1] = { 'health', ped } end
function SetPedSuffersCriticalHits(ped) calls[#calls + 1] = { 'critical', ped } end
function SetPedDiesWhenInjured(ped) calls[#calls + 1] = { 'dies', ped } end
function SetBlockingOfNonTemporaryEvents(ped) calls[#calls + 1] = { 'blocking', ped } end
function TaskSetBlockingOfNonTemporaryEvents(ped) calls[#calls + 1] = { 'task-blocking', ped } end

dofile('client/persistent_control.lua')
assert(#threads == 1)
pcall(threads[1])

assert(#calls > 0, 'static NPC should be configured')
for _, call in ipairs(calls) do
    assert(call[2] == 202, 'external NPC ownership must remain with the integrating resource')
end

print('persistent_control_ownership: ok')
