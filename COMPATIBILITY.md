# Compatibility

HumaLike works without a framework. Optional providers are detected at runtime
and can start or stop independently from the `humalike` resource.

## Server providers

| Domain | Provider | Resource | Priority | Notes |
| --- | --- | --- | ---: | --- |
| player | `standalone` | None | -1000 | Jobs are ACE grants (`humalike.job.<name>`); empty job requirements pass. |
| player | `esx` | `es_extended` | 100 | Supports ESX Legacy player identity and jobs. |
| player | `qbcore` | `qb-core` | 100 | Supports QBCore identity, jobs and duty state. |
| player | `qbox` | `qbx_core` | 100 | Supports Qbox identity, jobs and duty state. |
| inventory | `esx` | `es_extended` | 50 | Framework inventory fallback. |
| inventory | `ox_inventory` | `ox_inventory` | 100 | Supported with every player provider. |
| inventory | `qb_inventory` | `qb-inventory` | 100 | Intended for QBCore servers. |

Dispatch and custom action providers are registered by a separate integration
resource when the host server needs them.

## Client interaction providers

| Provider | Resource | Priority |
| --- | --- | ---: |
| `prompt` | None | -1000 |
| `ox_target` | `ox_target` | 10 |
| `qb_target` | `qb-target` | 10 |

## Voice resources

HumaLike carries NPC audio itself and never configures the server's voice
resource. It only observes these, when running, to keep its push to talk off
while the player is on a radio or in a call:

| Resource | Observed |
| --- | --- |
| `pma-voice` | Radio (`pma-voice:radioActive`) and phone calls (`callChannel` state) |
| `saltychat` | Radio transmit (`SaltyChat_RadioTrafficStateChanged`) |
| `yaca-voice` | Radio talk (`yaca:external:isRadioTalking`) and calls (`isInCall` export) |

Any other voice or phone resource reports its state through the client
export `SetVoiceBusy` described in `resources/humalike/INTEGRATIONS.md`.

## Selection

The domains are configured independently:

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
command reports where its interaction setting comes from: `server`,
`default` (received, left at `auto`) or `local` (not received yet).

Use `auto`, a provider name, or `none`. If multiple available providers share
the highest priority, `auto` remains unselected until the conflict is resolved.
For example, a server intentionally running both `ox_target` and `qb-target`
must select one explicitly.

Provider compatibility is based on the public API contract rather than a pinned
framework version. The release pipeline tests dependency absence, late start,
restart, stop, forced selection, ambiguity and fallback behavior.
