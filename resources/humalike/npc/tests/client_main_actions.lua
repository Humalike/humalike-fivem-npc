local handlers = {}
local hasControl = false
local calls = 0

AmbientPeds = { ['ambient-1'] = 101 }
AmbientNpcEntries = {
    ['ambient-1'] = { entity_id = 201, lease_token = 'lease-token' },
}
NpcActions = {
    wave = function(ped, params)
        assert(ped == 101 and params.speed == 2)
        calls = calls + 1
    end,
}

function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
function CreateThread() end
function DoesEntityExist(entity) return entity == 101 end
function NetworkHasControlOfEntity() return hasControl end
function HumalikeDebug() end
function GetCurrentResourceName() return 'humalike' end

dofile('client/main.lua')

local playAmbientAction = handlers['humalike:npc:playAmbientAction']
playAmbientAction('ambient-1', 201, 'lease-token', 'wave', { speed = 2 })
assert(calls == 0)

hasControl = true
playAmbientAction('ambient-1', 201, 'lease-token', 'wave', { speed = 2 })
assert(calls == 1)

playAmbientAction('ambient-1', 201, 'stale-token', 'wave', { speed = 2 })
assert(calls == 1)
