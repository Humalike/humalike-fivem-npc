local exported, posted = {}, {}
local loaded = { [7] = true, [8] = false }
local selectedProvider

function exports(name, callback) exported[name] = callback end
function RegisterNetEvent() end
function AddEventHandler() end
function CreateThread() end
function DoesEntityExist(entity) return entity == 101 or entity == 303 end
function NetworkGetNetworkIdFromEntity(entity) return entity == 303 and 53 or 0 end
function HumalikeDebug() end
HumalikeNpcEntityOwnership = {
    ExternalEntity = function(npcId) return npcId == 'npc-en' and 303 or nil end,
}
HumalikePlayer = { IsCharacterLoaded = function(playerId) return loaded[playerId] == true end }
HumalikeSelectedProvider = function(domain)
    assert(domain == 'actions')
    return selectedProvider
end
function HumalikePostPlayerEvent(playerId, event) posted[#posted + 1] = { playerId, event } end
NpcRegistry = {
    ['npc-en'] = { npc_id = 'npc-en', type = 'external', language = 'en' },
    ['npc-pl'] = { npc_id = 'npc-pl', type = 'static', entity_id = 101, language = 'pl' },
    ['npc-unbound'] = { npc_id = 'npc-unbound', type = 'external', language = 'en' },
    ['npc-despawned'] = { npc_id = 'npc-despawned', type = 'static', entity_id = 102, language = 'en' },
}
function HumalikeFindAmbientLease(npcId)
    if npcId == 'ambient-1' then
        return { npc_id = npcId, lease_token = 'lease-1', language = 'pl' }
    end
    return nil
end

dofile('../server/core/export_result.lua')
dofile('../server/core/text.lua')
dofile('../integration/server/actions.lua')
dofile('server/runtime_control.lua')
dofile('server/observations.lua')

local report = exported.ReportObservation
assert(type(report) == 'function')

assert(report('npc-en', 7, 'item_given', {}).error == 'unknown_observation')

selectedProvider = {
    Namespace = 'srp',
    Observations = {
        item_given = {
            fields = { item = 'string', quantity = 'integer', stolen = 'boolean', weight = 'number' },
            template = {
                en = 'the character handed you {quantity} x {item} ({weight} kg)',
                pl = 'postać wręczyła ci {quantity} x {item} ({weight} kg)',
            },
        },
        door_unlocked = { fields = {}, template = { pl = 'ktoś otworzył drzwi' } },
    },
}

assert(report('npc-en', 0, 'item_given').error == 'invalid_player')
assert(report('npc-en', 7.5, 'item_given').error == 'invalid_player')
assert(report('npc-en', 8, 'item_given').error == 'character_not_loaded')
assert(report('npc-missing', 7, 'item_given').error == 'npc_not_found')
assert(report(42, 7, 'item_given').error == 'npc_not_found')
assert(report('npc-unbound', 7, 'item_given').error == 'npc_not_bound')
assert(report('npc-despawned', 7, 'item_given').error == 'npc_not_bound')
assert(report('npc-en', 7, 'srp:item_given').error == 'unknown_observation')
assert(report('npc-en', 7, 'item_given', 'amulet').error == 'invalid_fields')
assert(report('npc-en', 7, 'item_given', { item = 'amulet' }).error:match('^invalid_field:'))
local full = { item = 'amulet', quantity = 1, stolen = false, weight = 0.5 }
local function with(overrides)
    local fields = {}
    for key, value in pairs(full) do fields[key] = value end
    for key, value in pairs(overrides) do fields[key] = value end
    return fields
end
assert(report('npc-en', 7, 'item_given', with({ quantity = 1.5 })).error == 'invalid_field:quantity')
assert(report('npc-en', 7, 'item_given', with({ item = ('x'):rep(65) })).error == 'invalid_field:item')
assert(report('npc-en', 7, 'item_given', with({ item = 'a\nb' })).error == 'invalid_field:item')
assert(report('npc-en', 7, 'item_given', with({ stolen = 'no' })).error == 'invalid_field:stolen')
assert(report('npc-en', 7, 'item_given', with({ weight = 0 / 0 })).error == 'invalid_field:weight')
assert(report('npc-en', 7, 'item_given', with({ weight = math.huge })).error == 'invalid_field:weight')
assert(report('npc-en', 7, 'item_given', with({ weight = 2 ^ 53 + 2 })).error == 'invalid_field:weight')
assert(report('npc-en', 7, 'item_given', with({ weight = 1e300 })).error == 'invalid_field:weight')
assert(report('npc-en', 7, 'item_given', with({ quantity = -(2 ^ 53) - 2 })).error == 'invalid_field:quantity')
assert(report('npc-en', 7, 'item_given', with({ quantity = math.mininteger })).error == 'invalid_field:quantity')
assert(report('npc-en', 7, 'item_given', with({ quantity = math.maxinteger })).error == 'invalid_field:quantity')
assert(report('npc-en', 7, 'item_given', with({ item = 'a\u{85}b' })).error == 'invalid_field:item')
assert(report('npc-en', 7, 'item_given', with({ item = 'a\u{9F}b' })).error == 'invalid_field:item')
assert(report('npc-en', 7, 'item_given', with({ extra = 1 })).error == 'unknown_field:extra')
assert(report('npc-en', 7, 'item_given', full, 'react').error == 'invalid_options')
assert(report('npc-en', 7, 'item_given', full, { react = 'yes' }).error == 'invalid_options')
assert(#posted == 0)

local result = report('npc-en', 7, 'item_given', with({ item = '  amulet ' }))
assert(result.ok and result.apiVersion == 1, result.error)
assert(result.value.key == 'srp:item_given')
assert(result.value.text == 'the character handed you 1 x amulet (0.5 kg)', result.value.text)
assert(#posted == 1 and posted[1][1] == 7)
local event = posted[1][2]
assert(event.type == 'server_observation' and event.npc_id == 'npc-en')
assert(event.key == 'srp:item_given' and event.text == result.value.text)
assert(event.lease_token == nil and event.react == true)
assert(event.fields.item == 'amulet' and event.fields.quantity == 1
    and event.fields.stolen == false and event.fields.weight == 0.5)
assert(math.type(event.fields.quantity) == 'integer')

result = report('npc-pl', 7, 'item_given', with({ weight = 2.0 }), { react = false })
assert(result.value.text == 'postać wręczyła ci 1 x amulet (2 kg)', result.value.text)
assert(posted[2][2].react == false)
result = report('npc-pl', 7, 'item_given', with({ weight = 2 ^ 53 }))
assert(result.value.text == 'postać wręczyła ci 1 x amulet (9007199254740992 kg)', result.value.text)
result = report('npc-pl', 7, 'item_given', with({ quantity = -(2 ^ 53), item = 'a\u{A0}b' }))
assert(result.value.text == 'postać wręczyła ci -9007199254740992 x a\u{A0}b (0.5 kg)', result.value.text)

-- No template for the language falls back; no fields omits the key.
result = report('npc-en', 7, 'door_unlocked')
assert(result.value.text == 'ktoś otworzył drzwi')
assert(posted[5][2].fields == nil)

result = report('ambient-1', 7, 'item_given', full)
assert(result.ok and posted[6][2].lease_token == 'lease-1')
assert(posted[6][2].text:match('^postać'))

selectedProvider.Observations.hoard = {
    fields = { item = 'string' },
    template = { en = ('{item} '):rep(16) .. ('x'):rep(304) },
}
local hoard = report('npc-en', 7, 'hoard', { item = ('y'):rep(64) })
assert(hoard.error == 'text_too_long', tostring(hoard.error))
assert(#posted == 6)
assert(report('npc-en', 7, 'hoard', { item = ('y'):rep(37) }).ok)
assert(utf8.len(posted[7][2].text) == 912)

print('observations: ok')
