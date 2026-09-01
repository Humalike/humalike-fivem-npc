# HumaLike for FiveM

HumaLike adds persistent, voice-enabled AI characters to FiveM. The single
`humalike` resource handles NPC lifecycle, world context, gameplay actions and
WebRTC voice while keeping framework-specific behavior behind optional
providers.

## What it includes

- Persistent and ambient AI NPCs synchronized through OneSync.
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
need to be configured manually.

Detailed installation and configuration documentation is available at
[docs.humalike.com](https://docs.humalike.com/).

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

See [COMPATIBILITY.md](COMPATIBILITY.md) for provider names, selection behavior
and optional dependencies. Custom integrations should use the public API
described in
[`resources/humalike/INTEGRATIONS.md`](resources/humalike/INTEGRATIONS.md); a
minimal separate-resource template is available in
[`examples/humalike-adapter`](examples/humalike-adapter).

## Diagnostics

Run `humalike_status` in the server console to inspect runtime health and every
server provider domain. Run the same command in the FiveM client console to
inspect the selected interaction provider.

Verbose runtime logging is disabled by default and can be enabled temporarily:

```cfg
setr humalike_debug 1
```

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

## Security

Do not report vulnerabilities in a public issue. Use
[GitHub private vulnerability reporting](https://github.com/Humalike/humalike-fivem-npc/security/advisories/new).

## License

HumaLike for FiveM is source-available under the
[PolyForm Shield License 1.0.0](LICENSE.md). You may use and modify it as part
of a monetized FiveM server. You may not use it to provide a product or service
that competes with HumaLike's AI NPC software or services. See [NOTICE](NOTICE)
and the license terms for the authoritative conditions.
