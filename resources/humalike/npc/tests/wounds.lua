
unpack = unpack or table.unpack

local handlers, sent, reports = {}, {}, {}

function RegisterNetEvent() end
function AddEventHandler(name, fn) handlers[name] = fn end
function TriggerClientEvent(name, target, npcId, payload)
    sent[#sent + 1] = { name = name, target = target, npc_id = npcId, payload = payload }
end
function HumalikeDebug() end
function GetHashKey(name)
    local hash = 5381
    for index = 1, #name do
        hash = (hash * 33 + name:byte(index)) % 4294967296
    end
    return hash
end
function GetConvar(_, fallback) return fallback end
function DoesEntityExist(entity) return type(entity) == 'number' and entity > 0 end
function GetEntityRoutingBucket() return 0 end
function GetPlayerRoutingBucket() return 0 end
owner = -1
function NetworkGetEntityOwner() return owner end
local exported = {}
function exports(name, fn) exported[name] = fn end

Config = {}
dofile('config/wounds.lua')
Config.Wounds.Enabled = true
Config.Wounds.MaxWounds = 3
Config.Wounds.MinDamage = 5

HumalikePlayer = { IsCharacterLoaded = function() return true end }
AmbientNpcLeases = { [77] = { npc_id = 'npc-1', lease_token = 'tok' } }

function HumalikeReportNpcWounds(_, npcId, _, _, wounds)
    reports[#reports + 1] = { npc_id = npcId, wounds = wounds }
end

dofile('server/wounds.lua')

local damaged = handlers['humalike:npc:npcDamaged']
assert(damaged, 'npcDamaged handler missing')

local function hit(bone, weapon, damage, opts)
    opts = opts or {}
    source = opts.source or 5
    damaged(opts.npc_id or 'npc-1', opts.entity or 77, bone, weapon, damage)
end
local shotgun = GetHashKey('WEAPON_PUMPSHOTGUN') % 4294967296
hit(58271, shotgun, 60)            -- SKEL_L_Thigh
local held = HumalikeWoundsOf('npc-1')
assert(#held == 1, 'expected one wound, got ' .. #held)
assert(held[1].region == 'left_leg', 'region: ' .. held[1].region)
assert(held[1].kind == 'gunshot', 'kind: ' .. held[1].kind)
assert(held[1].severity == 'critical', 'severity: ' .. held[1].severity)
hit(31086, GetHashKey('WEAPON_SOME_DLC_RIFLE') % 4294967296, 10)
assert(HumalikeWoundsOf('npc-1')[1].kind == 'gunshot', 'unknown weapon should be a gunshot')
assert(HumalikeWoundsOf('npc-1')[1].region == 'head', 'head bone')
assert(HumalikeWoundsOf('npc-1')[1].severity == 'minor', 'minor band')
hit(40269, GetHashKey('WEAPON_KNIFE') % 4294967296, 20)
assert(HumalikeWoundsOf('npc-1')[1].kind == 'stab', 'knife should stab')
assert(HumalikeWoundsOf('npc-1')[1].severity == 'serious', 'middle band')
local before = #HumalikeWoundsOf('npc-1')
hit(28252, GetHashKey('WEAPON_KNIFE') % 4294967296, 90)   -- same region+kind, worse
local after = HumalikeWoundsOf('npc-1')
assert(#after == before, 'duplicate region+kind must not add an entry')
local upgraded
for _, wound in ipairs(after) do
    if wound.region == 'right_arm' and wound.kind == 'stab' then upgraded = wound end
end
assert(upgraded and upgraded.severity == 'critical', 'severity should upgrade in place')
Config.Wounds.MaxWounds = 2
hit(51826, shotgun, 100)
local capped = HumalikeWoundsOf('npc-1')
assert(#capped == 2, 'cap not applied: ' .. #capped)
for _, wound in ipairs(capped) do
    assert(wound.severity == 'critical', 'a minor wound survived the cap over a critical one')
end
Config.Wounds.MaxWounds = 3
HumalikeClearWounds('npc-1')
hit(31086, shotgun, 1)
assert(#HumalikeWoundsOf('npc-1') == 0, 'damage below the floor should not wound')
HumalikeClearWounds('npc-1')
hit(31086, shotgun, 50, { entity = 999 })
assert(#HumalikeWoundsOf('npc-1') == 0, 'unleased entity must not wound')
hit(31086, shotgun, 50, { npc_id = 'npc-other' })
assert(#HumalikeWoundsOf('npc-other') == 0, 'mismatched npc id must not wound')
HumalikeClearWounds('npc-1')
reports, sent = {}, {}
hit(31086, shotgun, 50)
assert(#reports == 1 and #reports[1].wounds == 1, 'edge should get the full list')
local broadcast = sent[#sent]
assert(broadcast.name == 'humalike:npc:npcWounds' and broadcast.target == -1,
    'wounds must be broadcast to everyone')
HumalikeClearWounds('npc-1')
assert(#HumalikeWoundsOf('npc-1') == 0, 'clear should empty the list')
hit(31086, shotgun, 50)
local snapshot = HumalikeWoundsOf('npc-1')
snapshot[1].region = 'tampered'
assert(HumalikeWoundsOf('npc-1')[1].region == 'head', 'callers must not share our state')
assert(type(exported.GetNpcWounds) == 'function', 'GetNpcWounds export missing')
assert(exported.GetNpcWounds('npc-1')[1].region == 'head', 'export should read wounds')

print('tests/wounds.lua ok')
HumalikeClearWounds('npc-1')
hit(31086, shotgun, 0)
local headshot = HumalikeWoundsOf('npc-1')
assert(#headshot == 1, 'a zero-damage headshot must still wound')
assert(headshot[1].region == 'head', headshot[1].region)
assert(headshot[1].severity == 'critical', 'headshot severity: ' .. headshot[1].severity)

HumalikeClearWounds('npc-1')
hit(58271, GetHashKey('WEAPON_BAT') % 4294967296, 0)
local beating = HumalikeWoundsOf('npc-1')
assert(beating[1].kind == 'blunt' and beating[1].severity == 'minor',
    'a bat to the leg reads gentler than a bullet')
HumalikeClearWounds('npc-1')
hit(31086, shotgun, 2)
assert(#HumalikeWoundsOf('npc-1') == 0, 'a real tiny number is still a scratch')

print('tests/wounds.lua zero-damage ok')
Config.Wounds.MaxWounds = -1
HumalikeClearWounds('npc-1')
hit(31086, shotgun, 50)
assert(#HumalikeWoundsOf('npc-1') == 0, 'a negative cap holds nothing, and terminates')
Config.Wounds.MaxWounds = 3
HumalikeClearWounds('npc-1')
owner = 999
hit(31086, shotgun, 50)
assert(#HumalikeWoundsOf('npc-1') == 0, 'a non-owner report must be refused')
owner = -1
hit(31086, shotgun, 50)
assert(#HumalikeWoundsOf('npc-1') == 1, 'an unowned ped still accepts the hit')
owner = 5
HumalikeClearWounds('npc-1')
hit(31086, shotgun, 50)
assert(#HumalikeWoundsOf('npc-1') == 1, 'the owner may report')
local resync = handlers['humalike:npc:requestWounds']
assert(resync, 'requestWounds handler missing')
sent = {}
source = 5
resync()
assert(#sent == 1 and sent[1].npc_id == 'npc-1' and sent[1].target == 5,
    'a joining player is sent the current wounds')

print('tests/wounds.lua review-findings ok')
