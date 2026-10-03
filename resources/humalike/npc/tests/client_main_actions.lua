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

-- The npc id of a ped comes from the lease index or the roster binding; the
-- ped's state bag is read only for a ped neither of them holds.
local bagReads = 0
function Entity(ped)
    return { state = setmetatable({}, { __index = function(_, key)
        assert(key == 'humalike_npc_id')
        bagReads = bagReads + 1
        return ped == 101 and 'from-the-bag' or nil
    end }) }
end
AmbientPedNpcIds = { [101] = 'ambient-1' }
LoadedPeds['static-1'] = 300
assert(HumalikeNpcIdOfPed(101) == 'ambient-1' and bagReads == 0, 'a leased ped is in the lease index')
assert(HumalikeNpcIdOfPed(300) == 'static-1' and bagReads == 0, 'a roster ped is in the roster binding')
AmbientPedNpcIds = {}
assert(HumalikeNpcIdOfPed(101) == 'from-the-bag' and bagReads == 1, 'a ped in neither is asked for its bag')
assert(HumalikeNpcIdOfPed(999) == nil and bagReads == 1, 'and a ped that is gone is nobody')
