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

Every `humalike_*` setting is a server convar. HumaLike sends the values the
shared config reads to each player when they join, so settings the client
uses (such as `humalike_interaction`, the label settings and the wounded
labels) work with `set`; `setr` also works. The client `humalike_status`
command reports whether it runs on the server's settings or its local
defaults.

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

The standalone player provider has no framework to ask about jobs, so it reads
FiveM's own ACE permissions: a player holds job `ambulance` when
`humalike.job.ambulance` is allowed for them. Empty job requirements pass. ACE
has no duty state, so a granted job counts as on duty:

```cfg
add_ace group.ems humalike.job.ambulance allow
add_principal identifier.license:0123456789abcdef group.ems
```

A player provider registered by an integration replaces this with the
framework's real job and duty state.

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
fields; a language without a template falls back to English. `spent` is a
field HumaLike writes, and a key names either an observation or an action. A
template is at most 400 characters and its worst-case render (64 characters
per string, 21 per number, 17 per integer, 5 per boolean) must stay within
912. A provider that implements no action may omit `RunAction`.
`RegisterProvider` returns `false` and prints the reason for a declaration it
refuses.

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

## Server-defined actions

The same provider can declare actions of its own. The model chooses them like
any built-in action, HumaLike gates each one on the observations the server
has reported, and the provider's `RunAction` performs it:

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
`give_map`. `description` (no square brackets) is the line the model reads.
`params` are values the model fills in, typed `string`, `integer` or
`boolean`, with `required` and, on a `string` or `integer` param, an optional
`enum` of bare words or integers. `player_id` is the addressee, filled by
HumaLike. `fixed` values never leave the server: they are merged over the
model's values before `RunAction` and may not be named `player_id`.
`requires` lists declared observations that must all have been reported for
this NPC and player within `within_s` seconds (default 600), matching `where`
on declared fields: a string, a boolean or a whole number exactly, or a bound
on a numeric field (`{ gte = 500 }`, `{ lte = 3 }`, both, or `{ sum_gte = 2 }`
which adds matching reports up). `consume` spends the matched facts once the
action is done. `locked_hint` is what the NPC is told, per language, while a
requirement is unmet. `limit = { per_player = 1, every_s = 86400, hint = {
en = '...' } }` caps how often one player may get the action. `uses_stock = {
item = 'map', quantity = 1 }` ties the action to the NPC's stock (below): it
locks at zero and each delivery takes its share. `auto = true` performs the
action as soon as its requirements hold, the next time the NPC answers that
player (needs a `consume = true` requirement and no `required` param, as the
model fills nothing in). `params_from = { amount = 'item_given.quantity' }`
hands `RunAction` values read from the consumed facts, numbers summed, never
from the model. Sizes and counts are capped; a declaration over a cap is
refused at `RegisterProvider` with the reason printed.

Admins enable a declared action per NPC in the dashboard like any other. The
resource re-declares everything whenever the actions provider changes, so
re-registering the provider or restarting the resource is enough for a change
to take effect. Every action reaches `RunAction` with the player within
`Config.ServerActions.MaxDistance` of the NPC. `RunAction` must return
exactly `true` to accept; anything else marks the invocation rejected and
HumaLike may push it again once its requirements hold, so returning `1` or
`'ok'` would perform it twice.

`exports.humalike:SetNpcStock(npcId, { map = 50, bread = 'unlimited' })`
replaces the NPC's whole shelf; an item left out is one the NPC has none of,
restocking is calling it again and `{}` empties the shelf. Items are the
server's own names (a letter, then `[a-z0-9_]`, at most 48 characters, at
most 32 of them: the model orders by them), counts whole numbers up to
1,000,000 or `'unlimited'`. The export waits for the answer, so
call it from an event handler or a thread once the NPC is on the roster
(`humalike:npc:ready`, or after binding an external one). `ok` means the
shelf is stored and `value.stock` is what was stored; otherwise `error` is
`invalid_npc`, `npc_not_found`, `npc_not_bound`, `invalid_stock`,
`invalid_item:<name>`, `invalid_count:<name>`, `too_many_items`,
`runtime_not_ready`, the backend's error code, or `http_<status>` when a
failed answer carries none.

## A shop counter

For NPCs that sell, declare a `Catalog` instead of one action per product.
HumaLike runs the order, the price, the payment and the change; the script
only hands things over and returns money:

```lua
exports.humalike:RegisterProvider('actions', {
    name = 'my_shop', apiVersion = 1, priority = 100,
    SupportedActions = {},
    Namespace = 'srp',
    Observations = {
        item_given = {
            fields = { item = 'string', quantity = 'integer' },
            template = { en = 'the character handed you {quantity} x {item}' },
        },
    },
    Catalog = {
        currency = 'cash',          -- the item_given `item` that counts as payment
        payment = 'item_given',     -- item (string) and quantity (integer) required
        items = {
            water = { price = 5 },
            bread = { price = 3 },
            pistol = { price = 150, limit = { per_player = 1, every_s = 86400 } },
        },
    },
    RunAction = function(action, source, npcCoords, params)
        if action == 'deliver' then
            -- All or nothing: return true only once every line and the change moved.
            local weight = 0
            for item, quantity in pairs(params.items) do
                weight = weight + exports.ox_inventory:Items(item).weight * quantity
            end
            if not exports.ox_inventory:CanCarryWeight(source, weight) then return false end
            local added = {}
            local function takeBack()
                for _, line in ipairs(added) do
                    exports.ox_inventory:RemoveItem(source, line.item, line.quantity)
                end
                return false
            end
            for item, quantity in pairs(params.items) do
                if exports.ox_inventory:AddItem(source, item, quantity) ~= true then
                    return takeBack()
                end
                added[#added + 1] = { item = item, quantity = quantity }
            end
            if params.change > 0
                and exports.ox_inventory:AddItem(source, params.currency, params.change) ~= true then
                return takeBack()
            end
            return true
        elseif action == 'refund' then
            return exports.ox_inventory:AddItem(source, params.currency, params.amount) == true
        end
        return false
    end,
})
```

An NPC sells whatever of the catalogue the server stocked it with
(`SetNpcStock`), at these prices. The model takes the order as one tag with
every line (`[srp:order water=10 pistol=1]`); HumaLike checks each line
against the shelf and the per-item limits, prices it, and tells the NPC the
total. Payment is a reported `item_given` of the currency. Once the money on
the counter covers the total, HumaLike calls `RunAction('deliver', source,
coords, { items = {...}, total, paid, change, currency })` and records the
sale; every line leaves the NPC's stock. Return `false` when the hand-over
cannot happen: nothing is recorded, the order and the money stay on the
counter, the NPC is told, and it is tried again on the next turn, so hand
over everything or nothing. A payment reported for a player who is not
within `Config.ServerActions.MaxDistance` of the NPC (or in another routing
bucket) is refused the same way until they are, so report a payment only for
a player standing there. Underpaid, the NPC is told what is owed. If the
customer backs out, `[srp:cancel_order]` calls `RunAction('refund', source,
coords, { amount, currency })` with exactly what is on the counter.
`deliver` and `refund` are declared for you and never offered to the model.
Catalog item names follow the stock's rule. The counter's keys are its own
in every namespace: `order`, `cancel_order`, `order_placed` and
`order_refused` cannot be declared as actions or observations, nor `deliver`
and `refund` as observations.

A server with its own shop menu places the order directly:
`exports.humalike:PlaceOrder(npcId, playerId, { water = 2, burger = 1 })`
sends the picked lines, checked and priced the same way, and the NPC
announces the total. Returns the export envelope with `no_catalog`,
`unknown_item:<name>`, `invalid_lines`, `invalid_quantity:<name>`,
`too_many_lines` or the usual player/NPC codes.

Keep customer-specific rewards, jobs, event names, dispatch payloads and UI
hooks in the integration resource. This makes updating `humalike` a complete
directory replacement without losing server customizations.
