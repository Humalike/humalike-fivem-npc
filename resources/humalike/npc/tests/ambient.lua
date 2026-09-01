Config = {
    AmbientBootstrapRadius = 150,
    AmbientMaxCandidatesPerReport = 128,
    AmbientScanIntervalMs = 2000,
}

local handlers = {}
local removed = {}
local conversions = 0
local threads = {}
local networkAvailable = false
local candidateReports = 0
local networkIdReads = 0
local playerPed = 0
local resolvedPed = 99
local stateTags = { [99] = 'old' }
local lastCandidates = nil
local networked42 = false

KnownNpcs = {
    ['static'] = { npc_id = 'static', voice_muted = false },
}

function RegisterNetEvent() end
function AddEventHandler(name, handler) handlers[name] = handler end
function CreateThread(handler) threads[#threads + 1] = handler end
function PlayerPedId() return playerPed end
function DoesEntityExist(entity) return entity == 1 or entity == 42 or entity == 99 end
function GetEntityType() return 1 end
function IsPedAPlayer() return false end
function IsPedHuman() return true end
function IsEntityDead() return false end
function IsPedFatallyInjured() return false end
function IsPedInAnyVehicle() return false end
function NetworkGetEntityIsNetworked(entity) return entity ~= 42 or networked42 end
function NetworkGetNetworkIdFromEntity(entity)
    networkIdReads = networkIdReads + 1
    return (entity == 99 or entity == 42 and networked42) and 53 or 0
end
function GetGamePool() return { 42 } end
function GetGameTimer() return 1000 end
function GetEntityModel() return 123 end
function GetEntityCoords(entity)
    return entity == 99 and { x = 0, y = 0, z = 0 } or { x = 1, y = 1, z = 1 }
end
function GetEntityHeading() return 0 end
function GetNameOfZone() return 'TEST' end
function NetworkDoesEntityExistWithNetworkId() return networkAvailable end
function NetworkGetEntityFromNetworkId()
    conversions = conversions + 1
    return resolvedPed
end
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
function HumalikeReportAmbientCandidates(candidates)
    assert(type(candidates) == 'table')
    candidateReports = candidateReports + 1
    lastCandidates = candidates
end

dofile('client/ambient.lua')

AmbientPeds.old = 42
AmbientNpcEntries.old = {
    entity_id = 100,
    network_id = 20,
    routing_bucket = 0,
    lease_token = 'old-token',
}

handlers['humalike:npc:ambientLeases']({
    enabled = true,
    discovery_radius = 150,
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
assert(conversions == 3)
assert(AmbientPeds.new == 99 and AmbientNpcEntries.new.lease_token == 'new-token')
assert(AmbientNpcEntries.new.language == 'en')
assert(stateTags[99] == 'new')
resolvedPed = 42
networked42 = true
networkAvailable = true
handlers['humalike:npc:ambientLeases']({
    enabled = true,
    discovery_radius = 150,
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

local scanWaits = 0
playerPed = 1
function GetGamePool() return { 42 } end
Wait = function()
    scanWaits = scanWaits + 1
    if scanWaits > 1 then error('stop scan thread') end
end
pcall(threads[3])
assert(candidateReports == 1,
    'ambient discovery reports candidates without requiring a framework selection')
assert(#lastCandidates == 1 and lastCandidates[1].network_id == 53,
    'an active ambient ped must renew its edge lease on every discovery scan')

handlers['humalike:npc:voiceMuteSnapshot'](1, { static = true, new = false })
assert(KnownNpcs.static.voice_muted == true)
assert(AmbientNpcEntries.new.voice_muted == false)
handlers['humalike:npc:voiceMuteSnapshot'](1, { static = false, new = true })
assert(KnownNpcs.static.voice_muted == true)
assert(AmbientNpcEntries.new.voice_muted == false)
handlers['humalike:npc:ambientLeases']({ enabled = true, discovery_radius = 150, leases = {} })
scanWaits = 0
pcall(threads[3])
assert(candidateReports == 2 and #lastCandidates == 1,
    'a released ambient ped must be eligible on the next discovery scan')
