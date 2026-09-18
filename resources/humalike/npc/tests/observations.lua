-- ReportObservation: declared facts only, rendered in the NPC's language,
-- addressed to a roster NPC or a leased ambient body, posted as a
-- server_observation world event.
local exported, posted = {}, {}
local loaded = { [7] = true, [8] = false }
local selectedProvider

function exports(name, callback) exported[name] = callback end
function HumalikeDebug() end
HumalikePlayer = { IsCharacterLoaded = function(playerId) return loaded[playerId] == true end }
HumalikeSelectedProvider = function(domain)
    assert(domain == 'actions')
    return selectedProvider
end
function HumalikePostPlayerEvent(playerId, event) posted[#posted + 1] = { playerId, event } end
NpcRegistry = {
    ['npc-en'] = { npc_id = 'npc-en', type = 'external', language = 'en' },
    ['npc-pl'] = { npc_id = 'npc-pl', type = 'static', language = 'pl' },
}
function HumalikeFindAmbientLease(npcId)
    if npcId == 'ambient-1' then
        return { npc_id = npcId, lease_token = 'lease-1', language = 'pl' }
    end
    return nil
end

dofile('../server/core/export_result.lua')
dofile('../integration/server/actions.lua')
dofile('server/observations.lua')

local report = exported.ReportObservation
assert(type(report) == 'function')

-- No selected provider: nothing is declared.
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

-- Validation, in the order the export checks it.
assert(report('npc-en', 0, 'item_given').error == 'invalid_player')
assert(report('npc-en', 7.5, 'item_given').error == 'invalid_player')
assert(report('npc-en', 8, 'item_given').error == 'character_not_loaded')
assert(report('npc-missing', 7, 'item_given').error == 'npc_not_found')
assert(report(42, 7, 'item_given').error == 'npc_not_found')
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
assert(report('npc-en', 7, 'item_given', with({ extra = 1 })).error == 'unknown_field:extra')
assert(report('npc-en', 7, 'item_given', full, 'react').error == 'invalid_options')
assert(report('npc-en', 7, 'item_given', full, { react = 'yes' }).error == 'invalid_options')
assert(#posted == 0)

-- Rendered in the NPC's language, integers without a trailing .0, data beside.
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

-- A language with no template falls back to English, then to whatever exists.
-- No declared fields: the key is omitted rather than sent as an empty table,
-- which would encode as a JSON array and fail the contract.
result = report('npc-en', 7, 'door_unlocked')
assert(result.value.text == 'ktoś otworzył drzwi')
assert(posted[3][2].fields == nil)

-- A leased ambient body carries its lease token so the edge can authorize it.
result = report('ambient-1', 7, 'item_given', full)
assert(result.ok and posted[4][2].lease_token == 'lease-1')
assert(posted[4][2].text:match('^postać'))

print('observations: ok')
