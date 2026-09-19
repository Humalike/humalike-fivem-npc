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

Client integrations can subscribe to
`humalike:voice:transmittingChanged(active)` to update a custom HUD.

## Server observations

Facts only the server knows (an item handed to an NPC, a door unlocked) are
declared on the actions provider and reported per occurrence. The NPC reads
the rendered line as a world event in its own language and can react to it.
Declare them on the actions provider the server already registers; only the
selected provider is consulted.

```lua
exports.humalike:RegisterProvider('actions', {
    name = 'my_actions', apiVersion = 1, priority = 100,
    SupportedActions = { 'hand_over_money' },
    RunAction = function(action, source, npcCoords, params) return true end,
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

`Namespace` prefixes every key on the wire (`srp:item_given`). Each observation
declares its `fields` (`string`, `integer`, `number` or `boolean`) and a
`template` per NPC language (`en`, `pl`) whose `{placeholders}` name declared
fields; a language without a template falls back to English. A template is at
most 400 characters and its worst-case render (64 characters per string, 21
per number, 17 per integer, 5 per boolean) must stay within 912. A provider
that implements no action may omit `RunAction`. `RegisterProvider` returns
`false` and prints the reason for a declaration it refuses.

`ReportObservation(npcId, playerId, key, fields, options)` accepts a live
roster NPC or an ambient body the server currently leases. Every declared
field is required and unknown fields are rejected: a `string` is at most 64
characters with no control characters, an `integer` is whole, and numbers are
finite and at most 2^53 in magnitude. It returns the export envelope:
`value.key` and `value.text` on success, or an `error` code (`invalid_player`,
`character_not_loaded`, `npc_not_found`, `npc_not_bound`,
`unknown_observation`, `invalid_fields`, `invalid_field:<name>`,
`unknown_field:<name>`, `invalid_options`, `text_too_long`). `ok = true` means
the observation is queued, not delivered. With `humalike_actions none` every
report returns `unknown_observation`. `options.react = false` files the fact
without a spoken reaction. With `humalike_developer_tools 1`,
`/humalike_dev observe <npc_uuid> <key> [field=value ...]` reports one by hand.

An observation is not gated on earshot or a `perception` hold; hold `speech`
to keep the NPC silent. A repeat of the same key within about 2.5 seconds is
filed but not spoken again.

Keep customer-specific rewards, jobs, event names, dispatch payloads and UI
hooks in the integration resource. This makes updating `humalike` a complete
directory replacement without losing server customizations.
