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
set humalike_audiohub auto
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

## Client audio hub (shared microphone)

Each NUI resource is its own CEF frame, so every resource that wants
microphone audio normally opens its own `getUserMedia` capture. Servers that
run a shared-microphone resource — one capture, relayed to consumer frames
over a loopback `RTCPeerConnection` — can register an audio hub adapter so
the HumaLike voice NUI attaches to that shared capture instead of opening a
second one. Without an adapter (the default), voice opens the device itself.

Register from the integration resource's client script:

```lua
exports.humalike:RegisterAudioHub({
    name = 'my_audiohub', apiVersion = 1, priority = 100,
    Available = function() return GetResourceState('my-audiohub') == 'started' end,
    Attach = function(id, options)
        -- options = { track = boolean, level = boolean }
        -- Forward to the hub; return false to refuse (voice falls back to
        -- its own capture). Any other return value counts as accepted.
    end,
    Detach = function(id) end,
    Signal = function(id, payload)
        -- payload is an opaque WebRTC offer/answer/ICE blob from the voice
        -- NUI. Only negotiation crosses this bridge; audio never does.
    end,
})
```

The adapter pushes hub responses back with
`exports.humalike:AudioHubDeliver(id, action, data)`, where `action` is
`'signal'` (a WebRTC blob for the voice NUI) or `'state'` (a table like
`{ capturing = boolean, error = string?, pending = boolean? }`). Delivery is
accepted only from the resource that owns the session, and only for ids
HumaLike attached. Report `pending = true` while a capture attempt (for
example a permission prompt) is in flight, and `capturing = false` with an
`error` when the hub cannot supply audio, so voice can react before its
negotiation timeout.

Semantics:

- The hub owns the capture device and constraints; the voice input-device
  selection applies only to the local fallback.
- If no adapter is available the attach is answered `available = false` and
  voice opens its own capture — standalone behavior is unchanged.
- If an adapter accepted the attach but the relay fails, voice retries
  against the hub and then reports an error instead of opening a second
  concurrent capture alongside the hub's.
- When the adapter's resource stops or unregisters, open sessions receive a
  `state` of `capturing = false, error = 'hub-stopped'` automatically.
- Adapters follow the shared lifecycle: register on their own start and again
  after `humalike:integration:ready`. `UnregisterAudioHub(name)` removes an
  adapter; `GetAudioHubStatus()` reports the setting, resolution state,
  selected adapter and open session count.
- Voice currently attaches with `options.track = true, level = false`; the
  `level` flag is reserved for future loudness-only consumers.

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
local lease, err = exports.humalike:AcquireNpcControl(npcId, {
    domains = { 'movement', 'animation' },
    ttlMs = 30000,
    reason = 'hostage_scenario',
})
```

The domains are `movement`, `animation`, `speech`, `perception` and `all`.
`all` must be requested alone. A conflicting lease is rejected atomically.
TTL must be between 1 second and 5 minutes.

```lua
local renewed, renewErr = exports.humalike:RenewNpcControl(lease.id, 30000)
local released, releaseErr = exports.humalike:ReleaseNpcControl(lease.id)
local state, stateErr = exports.humalike:GetNpcRuntimeState(npcId)
```

Only the resource that acquired a lease can renew or release it. Leases expire
at their TTL, when their owner resource stops, when the NPC disappears, or when
an ambient NPC receives a new runtime incarnation. `GetNpcRuntimeState` returns
the current entity and network ID, routing bucket, NPC kind, AI status and the
owner of each controlled domain. Callers should use `networkId` across event or
network boundaries; `entity` is only a local server handle.

## Neutral events

Server integrations can translate their own event bus with
`exports.humalike:ReportPlayerEvent(playerId, event)`. Supported event types are
`rp_action`, `identity_document_shown`, `item_dropped`, `item_picked_up`, the
three badge events, and `hands_raised`/`hands_lowered`. HumaLike validates the
payload and loaded character before forwarding it.

Client integrations can subscribe to
`humalike:voice:transmittingChanged(active)` to update a custom HUD.

Keep customer-specific rewards, jobs, event names, dispatch payloads and UI
hooks in the integration resource. This makes updating `humalike` a complete
directory replacement without losing server customizations.
