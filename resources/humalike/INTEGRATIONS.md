# HumaLike integrations

HumaLike runs standalone. Servers can add framework-specific behaviour without
editing this resource by starting a separate integration resource that depends
on `humalike` and registers only the domains it owns.

Provider selection is independent per domain and defaults to the highest
priority available provider:

```cfg
set humalike_player auto
set humalike_inventory auto
set humalike_dispatch auto
set humalike_actions auto
set humalike_interaction auto
```

Use a provider name to force one domain, or `none` to disable it. If multiple
available providers share the highest priority in `auto`, the domain remains
unselected until the conflict is resolved. This avoids silently choosing the
wrong host integration.

## Server providers

Register from the integration resource's server script. Callbacks execute in
that resource and may use its framework exports.

```lua
exports.humalike:RegisterProvider('player', {
    name = 'my_player_provider',
    apiVersion = 1,
    priority = 100,
    Available = function() return GetResourceState('my-core') == 'started' end,
    GetCharacterId = function(source) return 'character-id' end,
    GetCharacterName = function(source) return 'Character Name' end,
    IsCharacterLoaded = function(source) return true end,
    HasJob = function(source, jobNames, requireDuty) return false end,
    Notify = function(source, message, kind) end,
})
```

The remaining domains are deliberately separate. The player provider translates
only active-character identity, loaded state and job membership; it does not
select inventory, dispatch, actions or interactions:

```lua
exports.humalike:RegisterProvider('inventory', {
    name = 'my_inventory', apiVersion = 1, priority = 100,
    AddItem = function(source, itemName, quantity, metadata) return true end,
})

exports.humalike:RegisterProvider('dispatch', {
    name = 'my_dispatch', apiVersion = 1, priority = 100,
    Report = function(kind, payload) return true end,
})

exports.humalike:RegisterProvider('actions', {
    name = 'my_actions', apiVersion = 1, priority = 100,
    SupportedActions = { 'hand_over_money' },
    RunAction = function(action, source, npcCoords, params) return true end,
})
```

`Available` is optional in every domain. Providers are removed automatically
when their owner resource stops, and HumaLike falls back to the next available
provider. An integration may also call
`UnregisterProvider(domain, providerName)` explicitly.

`GetProviderStatus()` returns `apiVersion`, a compact `selected` map and detailed
`domains`. Each domain contains its setting, resolution state,
reason, selected provider and all registered candidates.

Provider names are lowercase. A callback failure marks the selected domain as
`degraded`; repeated failures are rate-limited in the server log. A successful
callback clears that state.

### Built-in server providers

The public resource detects these optional dependencies without requiring an
adapter resource:

| Domain | Provider | Dependency | Priority |
| --- | --- | --- | ---: |
| player | `standalone` | none | -1000 |
| player | `esx` | `es_extended` | 100 |
| player | `qbcore` | `qb-core` | 100 |
| player | `qbox` | `qbx_core` | 100 |
| inventory | `esx` | `es_extended` | 50 |
| inventory | `ox_inventory` | `ox_inventory` | 100 |
| inventory | `qb_inventory` | `qb-inventory` | 100 |

Framework and inventory selection are independent. ESX's built-in inventory is
the low-priority fallback; `ox_inventory` wins when installed. Starting or
stopping a dependency updates the selection without restarting HumaLike. Two
dedicated inventories at the same priority make `auto` ambiguous instead of
silently choosing one. The same applies when more than one player framework is
running; explicitly configure the intended provider.

ESX has no standard duty state. Its provider treats matching job membership as
on duty unless the server's job object explicitly exposes a false `onduty` or
`onDuty` value. QBCore and Qbox require `job.onduty == true` when duty is
required.

## Client interaction provider

The built-in E prompt is always available. `ox_target` and `qb-target` are
detected when running and both have priority 10. If both are installed, select
one explicitly with `humalike_interaction ox_target` or
`humalike_interaction qb-target`. A custom client UI can register:

```lua
exports.humalike:RegisterInteractionProvider({
    name = 'my_target', apiVersion = 1, priority = 100,
    Available = function() return GetResourceState('my-target') == 'started' end,
    watchedResources = { 'my-target' },
    Add = function(id, entity, options) return true end,
    Remove = function(id) end,
    Progress = function(durationMs, label) return true end,
})
```

Each option contains `text`, optional `icon`, `canInteract(entity)` and
`onSelect(entity)`. `Progress` is optional.

Client providers can call `UnregisterInteractionProvider(name)` explicitly.
`GetInteractionProviderStatus()` reports the client runtime epoch and current
selection.

## Resource lifecycle

HumaLike publishes `humalike:integration:ready` independently on the server and
client after each HumaLike resource start. The payload contains `apiVersion`
and a new `runtimeEpoch`. An integration should register on its own start and
register again when it receives this event. Registration by the same owner and name is
idempotent.

Stopping an integration removes its server and client providers. Stopping a
dependency re-evaluates `Available`, while restarting HumaLike produces a new
epoch and lets integrations rebuild their registrations. Interaction callbacks
are removed before HumaLike stops and whenever the selected provider changes.

The standalone player provider has no job system. Empty job requirements pass;
any configured job requirement is denied until a player provider implements
`HasJob`.

## NPC runtime control

Server resources can temporarily take over selected AI domains without
changing the NPC definition or its entity binding:

```lua
local result = exports.humalike:AcquireNpcControl(npcId, {
    domains = { 'movement', 'animation' },
    ttlMs = 30000,
    reason = 'hostage_scenario',
})
if not result.ok then
    print(('HumaLike control failed: %s'):format(result.error))
    return
end
local lease = result.value
```

The domains are `movement`, `animation`, `speech`, `perception` and `all`.
`all` must be requested alone. A conflicting lease is rejected atomically.
TTL must be between 1 second and 5 minutes.

```lua
local renewed = exports.humalike:RenewNpcControl(lease.id, 30000)
local released = exports.humalike:ReleaseNpcControl(lease.id)
local state = exports.humalike:GetNpcRuntimeState(npcId)
```

Only the resource that acquired a lease can renew or release it. Leases expire
at their TTL, when their owner resource stops, when the NPC disappears, or when
an ambient NPC receives a new runtime incarnation. `GetNpcRuntimeState` returns
the current entity and network ID, routing bucket, NPC kind, AI status and the
owner of each controlled domain. Callers should use `networkId` across event or
network boundaries; `entity` is only a local server handle.

`exports.humalike:ListNpcRuntimeStates()` returns the same success envelope with
an array of states for the current synced roster, including unbound external
NPCs. Each state also includes `name` and configured `model`; rows are sorted by
`npcId`. It does not return credentials or NPC definitions absent from the roster.

`ListNpcRuntimeStates` also includes the current server ambient AI leases as
`kind = "ambient"`, deduplicated by NPC ID. These rows use a generic name and
model hash string; no lease tokens are returned. This is current runtime state,
not player encounter history.

## NPC entity ownership

A server resource may attach an external HumaLike identity to a networked ped
that it owns. Configure the NPC as `external` in the dashboard; the integrating
resource retains lifecycle and movement ownership. HumaLike never spawns,
positions, freezes or deletes the entity:

```lua
local result = exports.humalike:BindNpcEntity(npcId, networkId, {
    routingBucket = 0,
})
if not result.ok then
    print(('HumaLike bind failed: %s'):format(result.error))
    return
end
local binding = result.value

local released = exports.humalike:UnbindNpcEntity(binding.id)
```

The entity must exist, be a non-player ped, use the NPC's configured model and
match the optional routing bucket. An NPC and a network entity can each have
only one external binding. Unbind removes HumaLike state and leaves the ped
untouched. The NPC remains offline until it is bound again. Repeating the same
bind from the same resource returns the existing binding. Static and dynamic
NPCs cannot be externally bound.

Static NPCs can also be removed from the runtime without deleting their
definition:

```lua
local despawn = exports.humalike:DespawnNpc(npcId)
local restored = exports.humalike:RespawnNpc(npcId)
```

These exports return one MessagePack-safe result because FiveM resource exports
carry one return value. Successful results use `{ apiVersion = 1, ok = true,
value = ... }`; failures use `{ apiVersion = 1, ok = false, error = "..." }`.

Binding and despawn ownership belongs to the invoking resource. Its external
bindings are detached and its static despawns restored when it stops. A
resource that survives a HumaLike restart must bind again after
`humalike:npc:ready`. This server event fires after the first successful roster
sync for each HumaLike runtime generation.

## Neutral events

Server integrations can translate their own event bus with
`exports.humalike:ReportPlayerEvent(playerId, event)`. Supported event types are
`rp_action`, `identity_document_shown`, `item_dropped`, `item_picked_up`, the
three badge events, and `hands_raised`/`hands_lowered`. HumaLike validates the
payload and loaded character before forwarding it.

## Server observations

Facts only the server knows -- an item handed to an NPC, a door unlocked, a job
finished -- are declared on the actions provider and reported per occurrence.
The NPC reads the rendered line as a world event in its own language and can
react to it; a player saying "I gave you the amulet" is talk, a reported
observation is fact.

```lua
exports.humalike:RegisterProvider('actions', {
    name = 'my_actions', apiVersion = 1, priority = 100,
    SupportedActions = {},
    Namespace = 'srp',
    Observations = {
        item_given = {
            fields = { item = 'string', quantity = 'integer' },
            template = {
                en = 'the character handed you {quantity} x {item}',
                pl = 'postać wręczyła ci {quantity} x {item}',
            },
        },
    },
})

-- from your inventory hook, once the transfer is real:
local result = exports.humalike:ReportObservation(npcId, source, 'item_given', {
    item = 'amulet', quantity = 1,
})
```

`Namespace` (`^[a-z][a-z0-9]{1,15}$`) prefixes every key on the wire
(`srp:item_given`), so a server key never collides with a built-in event.
Observation keys and field names match `^[a-z][a-z0-9_]{0,31}$`; up to 32
observations with up to 8 fields each, typed `string` (≤ 64 characters),
`integer`, `number` or `boolean`. Every declared field is required when
reporting and unknown fields are rejected. `template` holds one line per NPC
language (`en`, `pl`; ≤ 400 characters) whose `{placeholders}` name declared
fields; an NPC whose language has no template reads the English one.
`RunAction` is optional for a provider that implements no action.

`ReportObservation(npcId, playerId, key, fields, options)` accepts a roster NPC
(static, or external and bound) or an ambient body the server currently leases,
and returns the export envelope: `value.key` and `value.text` on success, or an
`error` code (`invalid_player`, `character_not_loaded`, `npc_not_found`,
`unknown_observation`, `invalid_field:<name>`, `unknown_field:<name>`,
`invalid_options`). `options.react = false` files the fact without a spoken
reaction. With `humalike_developer_tools 1`, `/humalike_dev observe <npc_uuid>
<key> [field=value ...]` reports one by hand.

## Server-defined actions

Beside reporting facts, the same provider can declare deeds of its own. The
model chooses them like any catalogue action, HumaLike gates each one on the
facts the server has reported, and the server's `RunAction` performs it:

```lua
exports.humalike:RegisterProvider('actions', {
    name = 'my_actions', apiVersion = 1, priority = 100,
    SupportedActions = {},
    Namespace = 'srp',
    Observations = {
        item_given = {
            fields = { item = 'string', quantity = 'integer' },
            template = { en = 'the character handed you {quantity} x {item}' },
        },
    },
    Actions = {
        give_map = {
            name = 'Give the treasure map',
            description = 'Hand the player the map to the hidden chest.',
            params = { copies = { type = 'integer', enum = { 1, 2 } } },   -- the model fills these
            fixed = { item = 'treasure_map' },                             -- the script fixes these
            requires = {
                { observation = 'item_given', where = { item = 'amulet' }, within_s = 600,
                  consume = true },
            },
            locked_hint = { en = 'Only once the amulet is in your hands.' },
        },
    },
    RunAction = function(action, source, npcCoords, params)
        if action ~= 'give_map' then return false end
        return exports.ox_inventory:AddItem(source, params.item, params.copies or 1)
    end,
})
```

The key reaches the model as `srp:give_map` and comes back to `RunAction` as
`give_map`. `description` (≤ 400 characters, no square brackets) is the line
the model reads. `params` (≤ 4) are values the model writes inline in its tag
-- `[srp:give_map copies=2]` -- typed `string`, `integer` or `boolean`, with an
optional `enum` (≤ 16 bare words or integers) and `required`; `player_id` is
always filled by HumaLike with the addressee. `fixed` values (≤ 16) never leave
the server: they are merged under the model's values before `RunAction`, and
always win. `requires` (≤ 4, all must hold) name declared observations that
must have been reported for this NPC and the player it is answering, matching
`where` on declared fields -- a scalar exactly, or a bound on a numeric field
(`quantity = { gte = 500 }`, `{ lte = 3 }`, or both) -- within `within_s`
(5–3600, default 600) seconds;
`consume` spends the fact once the deed is done, so one amulet buys one map.
`locked_hint` is what the NPC is told, per language, while a requirement is
unmet; a player saying it happened never unlocks anything. `limit = {
per_player = 1, every_s = 86400, hint = { en = '...' } }` caps how often one
player may get the deed (counted from the deeds HumaLike recorded, so chat
cannot reset it); no limit unless declared.

Admins enable a declared action per NPC in the dashboard like any other. The
resource re-declares everything on every `report_capabilities`, so a changed
or removed action takes effect on the next resource start. `RunAction`
returning `false` marks the invocation rejected; prefer expressing state as
observations over refusing at run time, since the NPC has already spoken.

Client integrations can subscribe to
`humalike:voice:transmittingChanged(active)` to update a custom HUD.

Keep customer-specific rewards, jobs, event names, dispatch payloads and UI
hooks in the integration resource. This makes updating `humalike` a complete
directory replacement without losing server customizations.
