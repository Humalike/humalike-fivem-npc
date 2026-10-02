# HumaLike for FiveM

HumaLike adds persistent, voice-enabled AI characters to FiveM. The single
`humalike` resource handles NPC lifecycle, world context, gameplay actions and
WebRTC voice while keeping framework-specific behavior behind optional
providers.

## What it includes

- Persistent and ambient AI NPCs synchronized through OneSync.
- HumaLike-owned street population: planned bodies spawn on pavement and
  player contact (a bump, a knock-down) reaches the AI as a world event.
- Proximity voice with direct NPC targeting and in-vehicle routing.
- World-state collection, NPC actions, injuries and interactions.
- Standalone operation with optional ESX, QBCore, Qbox, inventory and target
  integrations.
- A versioned provider API for server-specific adapters.

## Requirements

- A current FXServer build with OneSync enabled.
- A HumaLike server license.
- No framework dependency for standalone use.

## Installation

Use a verified release archive rather than copying this development tree. Put
the included `humalike` directory in your server's resources directory, then add
the following to `server.cfg`:

```cfg
set humalike_license_key "ak_secret_replace_me"
ensure humalike
```

The license is server-only and must use `set`, never `setr`. HumaLike exchanges
it for short-lived runtime credentials; service URLs and voice secrets do not
need to be configured manually. The resource becomes ready only when the
control plane returns complete edge and voice assignments. Each assignment
must include its assignment ID, node ID, node boot ID and positive integer
generation. A malformed successful bootstrap response stops a newly started
resource, so a strict release cannot run against an older control-plane
contract. Updating an installed resource follows the Update section of the
archive's `INSTALL.md` (`refresh`, then `restart humalike`).

For the first cutover of an existing server, keep the assignment-capable
transition control plane running while healthy edge and voice nodes start.
Enable both sharding planes and verify complete active assignments, then deploy
the strict control plane and this resource. The transition release is not part
of the final architecture. There is no static runtime fallback after cutover;
reversing this order intentionally leaves the resource stopped instead of
issuing or accepting assignment-unbound credentials.

Releases update themselves on start: HumaLike checks GitHub, verifies the
release's Ed25519 signature and installs it. Add
`add_ace resource.humalike command.refresh allow` and
`add_ace resource.humalike command.ensure allow` so it can restart itself;
`humalike_auto_update` (`auto`, `notify`, `off`) and `humalike_version` (pin or
roll back) control it. See the archive's `INSTALL.md`.

Detailed installation and configuration documentation is available at
[docs.humalike.com/ai-npc](https://docs.humalike.com/ai-npc).

## Framework support

Each integration domain is selected independently. The default `auto` mode
selects the single highest-priority available provider and reports an ambiguity
instead of guessing when equally ranked providers conflict.

| Host setup | Player | Inventory | Interactions |
| --- | --- | --- | --- |
| Standalone | Built in | Optional | Built-in prompt |
| ESX | Built in | ESX or ox_inventory | Prompt or ox_target |
| QBCore | Built in | qb-inventory or ox_inventory | Prompt, qb-target or ox_target |
| Qbox | Built in | ox_inventory | Prompt or ox_target |

NPC voice is carried by the resource itself. pma-voice (verified), SaltyChat
and yaca (adapters not yet run in-game) are observed, when present, so
HumaLike's push to talk stays off during radio and phone use; other voice
resources report that through a client export.

See [COMPATIBILITY.md](COMPATIBILITY.md) for provider names, selection behavior
and optional dependencies. Custom integrations should use the public API
described in
[`resources/humalike/INTEGRATIONS.md`](resources/humalike/INTEGRATIONS.md); a
minimal separate-resource template is available in
[`examples/humalike-adapter`](examples/humalike-adapter).

## Diagnostics

Run `humalike_status` in the server console to inspect runtime health and every
server provider domain. Run the same command in the FiveM client console to
inspect the selected interaction provider and where its setting comes from.

Every `humalike_*` setting is a server convar written with `set`; `setr` is
never required. [COMPATIBILITY.md](COMPATIBILITY.md) explains how the values
reach the player's game.

The texts HumaLike shows players itself (the `/voice` panel, its own prompts)
are English by default; `set humalike_ui_language pl` switches them to Polish,
`es` to Spanish and `fr` to French.
Revive, mortuary and wound labels stay overridable one by one through their
own convars. NPC labels show a flag next to NPCs whose language differs from
the server's main one, `set humalike_npc_labels_default_language en` by
default.

Verbose runtime logging is disabled by default and can be enabled temporarily:

```cfg
set humalike_debug 1
```

While HumaLike owns the street population, GTA's random police stay off unless
`set humalike_population_cops true` is set; the convar is read every few seconds.

Some persona NPCs spawn at the wheel of a car or motorbike and drive around like
traffic; a player who talks to one makes it pull over. `set humalike_npc_vehicles
false` keeps everyone on foot (read every few seconds).

## Development

```sh
pnpm --dir resources/humalike install --frozen-lockfile
pnpm --dir resources/humalike check
pnpm --dir resources/humalike test:unit
pnpm --dir resources/humalike build
python3 -m unittest discover -s tests -v
python3 scripts/compose_release.py --output artifacts
```

The release composer reads committed files only and emits a deterministic ZIP,
SHA-256 checksum and provenance manifest. Deployment automation and credentials
are intentionally kept outside this public repository.

## Contributing

We welcome focused pull requests. Read [CONTRIBUTING.md](CONTRIBUTING.md) before
changing public contracts, integration behavior, or communication with
HumaLike. Discuss larger features with us on
[Discord](https://discord.gg/7bZFjm9aHH) before implementation.

## Security

Do not report vulnerabilities in a public issue. Use
[GitHub private vulnerability reporting](https://github.com/Humalike/humalike-fivem-npc/security/advisories/new).

## License

HumaLike for FiveM is source-available under the
[PolyForm Shield License 1.0.0](LICENSE.md). You may use and modify it as part
of a monetized FiveM server. You may not use it to provide a product or service
that competes with HumaLike's AI NPC software or services. See [NOTICE](NOTICE)
and the license terms for the authoritative conditions.
