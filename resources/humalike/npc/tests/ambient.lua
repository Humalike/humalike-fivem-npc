Config = {}

local handlers = {}
local removed = {}
local conversions = 0
local threads = {}
local networkAvailable = false
local resolvedPed = 99
local stateTags = { [99] = 'old' }

KnownNpcs = {
    ['static'] = { npc_id = 'static', voice_muted = false },
}

function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
function CreateThread(handler) threads[#threads + 1] = handler end
function DoesEntityExist(entity) return entity == 42 or entity == 99 end
function GetEntityType() return 1 end
function IsPedAPlayer() return false end
function NetworkDoesEntityExistWithNetworkId() return networkAvailable end
function NetworkGetEntityFromNetworkId()
    conversions = conversions + 1
    return resolvedPed
end
function NetworkGetNetworkIdFromEntity(ped) return ped == resolvedPed and 53 or 0 end
function Entity(entity)
    return {
        state = {
            humalike_npc_id = stateTags[entity],
            set = function(_, key, value)
                if key == 'humalike_npc_id' then stateTags[entity] = value end
            end,
        },
    }
end
function TriggerEvent(name, npcId)
    if name == 'humalike:npc:ambientPedRemoved' then removed[#removed + 1] = npcId end
end
function GetCurrentResourceName() return 'humalike' end

dofile('client/ambient.lua')
assert(#threads == 2, 'the lease binder and the snapshot request')

AmbientPeds.old = 42
AmbientNpcEntries.old = {
    entity_id = 100,
    network_id = 20,
    routing_bucket = 0,
    lease_token = 'old-token',
}

handlers['humalike:npc:ambientLeases']({
    enabled = true,
    leases = {
        {
            entity_id = 101,
            network_id = 53,
            routing_bucket = 0,
            npc_id = 'new',
            lease_token = 'new-token',
            language = 'en',
            voice_muted = true,
        },
    },
})

assert(conversions == 0)
assert(AmbientPeds.old == nil and AmbientNpcEntries.old == nil)
assert(#removed == 1 and removed[1] == 'old', ('removed=%d first=%s'):format(
    #removed, tostring(removed[1])))
assert(AmbientNpcEntries.new == nil) -- missing network entity was rejected

networkAvailable = true
local waits = 0
function Wait()
    waits = waits + 1
    if waits > 1 then error('stop thread') end
end
pcall(threads[1])
assert(conversions == 1, 'a bound lease is never resolved through its network id again')
assert(AmbientPeds.new == 99 and AmbientNpcEntries.new.lease_token == 'new-token')
assert(AmbientPedNpcIds[99] == 'new', 'the ped is indexed back to its npc id')
assert(AmbientNpcEntries.new.language == 'en')
assert(stateTags[99] == 'new')
resolvedPed = 42
handlers['humalike:npc:ambientLeases']({
    enabled = true,
    leases = {
        {
            entity_id = 101, network_id = 53, routing_bucket = 0,
            npc_id = 'new', lease_token = 'new-token', language = 'en',
            voice_muted = true,
        },
    },
})
assert(AmbientPeds.new == 42, 'a recycled network id must rebind to its current ped')
assert(stateTags[99] == nil and stateTags[42] == 'new')

handlers['humalike:npc:voiceMuteSnapshot'](1, { static = true, new = false })
assert(KnownNpcs.static.voice_muted == true)
assert(AmbientNpcEntries.new.voice_muted == false)
handlers['humalike:npc:voiceMuteSnapshot'](1, { static = false, new = true })
assert(KnownNpcs.static.voice_muted == true)
assert(AmbientNpcEntries.new.voice_muted == false)

handlers['humalike:npc:ambientLeases']({ enabled = true, leases = {} })
assert(AmbientPeds.new == nil and AmbientNpcEntries.new == nil,
    'a lease that left the snapshot releases its ped')
assert(removed[#removed] == 'new' and stateTags[42] == nil)

handlers['humalike:npc:ambientLeases']({
    enabled = true,
    leases = {
        { entity_id = 101, network_id = 53, routing_bucket = 0, npc_id = 'new',
            lease_token = 'new-token-2' },
    },
})
assert(AmbientPeds.new == 42 and AmbientNpcEntries.new.lease_token == 'new-token-2')
handlers['humalike:npc:ambientLeases']({ enabled = false })
assert(AmbientPeds.new == nil, 'a disabled snapshot clears every assignment')
handlers['onResourceStop']('humalike')
assert(next(AmbientPeds) == nil)
