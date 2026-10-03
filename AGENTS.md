# Agent guide

## Repository purpose

This repository is the public, canonical source of the HumaLike FiveM resource.
It must remain installable as a single `humalike` resource on a clean FXServer
without ESX, QBCore, Qbox, an inventory, or a target system.

The main areas are:

- `resources/humalike`: the product resource shipped to server owners;
- `resources/humalike/integration`: public provider contracts and built-in
  generic providers;
- `examples/humalike-adapter`: the starting point for external adapters;
- `release`: public installation material included in release archives;
- `scripts`: deterministic packaging and public-content validation;
- `tests` and component `tests` directories: development-only tests.

`resources/humalike/INTEGRATIONS.md` is the source of truth for the current
provider API. `COMPATIBILITY.md` records integrations supported by a release.

## Architecture rules

`resources/humalike` is a distributable product resource. Core gameplay must
not import, call, or subscribe to server-specific frameworks, inventories,
dispatch systems, targeting UIs, HUDs, or event buses directly.

- Route host concepts through the versioned provider APIs. Server providers
  are independent domains (`player`, `inventory`, `dispatch`, `actions`);
  client interaction providers use `RegisterInteractionProvider`. Do not infer
  one integration from another or add a monolithic framework bridge.
- Keep the standalone provider and built-in interaction prompt functional.
  Optional generic integrations may live in this resource, but the resource
  must start and provide its base feature set without them.
- Put customer- or server-specific translations in a separate integration
  resource which depends on `humalike` and registers providers through exports.
  Never add private resource names, exports, event names, economy rules, job
  object layouts, dispatch payloads, UI hooks, or voice hooks to public core.
- Integrations translate their native events into HumaLike's neutral contracts,
  such as `ReportPlayerEvent` and `humalike:voice:transmittingChanged`. Core
  must never emit a private server event directly.
- Keep authoritative mutations on the server. Treat client callbacks and
  events as untrusted, validate identifiers, types, ranges, entity ownership
  and distance, and expose the narrowest capability required.
- Providers must declare API version, name and priority, validate their full
  descriptor at registration, support late resource start/stop, and degrade to
  the next available provider. A missing optional capability must disable only
  that capability, not the whole resource.
- Integrations must register on their own start and after
  `humalike:integration:ready`. Treat `runtimeEpoch` changes as a fresh runtime;
  never assume either resource starts first.
- Execute every external provider callback through the protected integration
  call path. Clean up owned interactions before a resource stops and when its
  selected provider changes.
- Configuration belongs in convars or public framework-neutral config. Defaults
  must not encode one customer's jobs, economy, language, or resource names.
- Every integration change needs standalone tests, provider selection/fallback
  tests, and a repository search proving no new private dependency leaked into
  `resources/humalike`.

## Choosing where code belongs

- Put framework-neutral NPC, world, and voice behavior in the appropriate core
  module under `resources/humalike`.
- Put generally useful ESX, QBCore, Qbox, ox_inventory, qb-inventory,
  ox_target, or qb-target support in a built-in provider only when it relies on
  the dependency's public API and is useful to any server running it.
- Put server-specific jobs, permissions, economy behavior, dispatch formats,
  custom events, UI hooks, and compatibility shims in a separate adapter
  resource. Start from `examples/humalike-adapter`.
- Add a provider capability only when an existing neutral domain cannot express
  the behavior. Prefer extending a narrow domain over exposing a framework
  object or adding a generic escape hatch.
- Do not add optional framework dependencies to `fxmanifest.lua` as required
  dependencies. Detect them through provider availability and resource
  lifecycle.

## Provider behavior

- `player`, `inventory`, `dispatch`, `actions`, and client `interaction` are
  separate choices. Never select one domain because another domain uses the
  same framework.
- `auto` selects one highest-priority available provider. Equal highest
  priorities are an ambiguity, not permission to choose nondeterministically.
- `none` intentionally disables a domain. A named provider is a forced
  selection and must report unavailable clearly when its dependency is absent.
- The standalone player provider and built-in interaction prompt are fallbacks,
  not framework emulators. Standalone must never invent jobs, inventories, or
  character data.
- Provider registration must be idempotent. Test dependency absence, late
  start, stop, restart, HumaLike restart, fallback, forced selection, and
  ambiguity whenever selection or lifecycle code changes.

## Runtime and performance

- FiveM entity handles are local/runtime values. When an entity reference must
  cross a network boundary, send its network ID and validate the resolved
  entity before acting on it. Use `npc_id` for durable HumaLike identity.
- Avoid per-frame scans unless the feature genuinely needs frame accuracy.
  Reuse existing NPC registries, caches, spatial filters, and state-change
  events; emit network or NUI updates only when observable state changes.
- Periodic client work is a job of the shared pulse (`HumalikePulse.Every` in
  `world/client/pulse.lua`), not a thread of its own: a wake-up, a native and
  above all a NUI message each cost real frame time on every player's PC. Read
  the player through `HumalikePulse.Ped/Coords/Velocity/CamRot/CamCoord`, read
  NPC positions from `HumalikeWorldTrack`, and send recurring NUI messages
  pre-encoded through `HumalikePulse.Send`. Count a job's cadences on its
  `due` argument or on `HumalikePulse.Beat`, never on `now`: frames come late
  by a different amount each time. Per-frame work is a job of
  `HumalikePulse.EveryFrame` that returns false as soon as it is not needed.
- Keep hot-path diagnostics behind `humalike_debug`, rate-limit repeated
  failures, and never forward high-frequency client debug logs to the server.
- Keep server-authoritative validation for gameplay effects. Client-side target
  selection may improve responsiveness but does not authorize a mutation.
- Preserve independent component lifecycles: an unavailable edge, voice, or
  optional provider should degrade only the affected capability and recover
  without a full FXServer restart.

## Development workflow

1. Make the smallest framework-neutral change that satisfies the contract.
2. Add or update focused tests next to the affected Lua or TypeScript module.
3. Run Python tests, component Lua tests, Lua syntax validation, and relevant
   NUI checks. If the NUI changes, rebuild it and commit the generated
   `nui/host/dist` output.
4. Run `python3 scripts/audit_public_release.py` and search the diff for private
   hosts, server names, credentials, customer rules, and obsolete compatibility
   aliases.
5. Keep comments short and use them only for constraints or behavior that the
   code cannot make obvious.

Useful commands are documented in `README.md`. `humalike_status` should expose
enough provider state to diagnose configuration without enabling verbose logs.

## Releases

- Build distributable archives only with `scripts/compose_release.py` from a
  committed revision.
- Never copy the development tree directly to an FXServer. It contains tests,
  TypeScript sources and package-manager files that are excluded from releases.
- Release archives must be deterministic and pass the public-content audit.
- Environment-specific promotion and deployment automation belongs in the
  private operations repository, not in this public repository.
- GitHub Releases are created in this repository from version tags. Private
  deployment systems may consume a published archive but must not rebuild it.
- Keep product and resource versions aligned in `release.lock.json` and
  `resources/humalike/fxmanifest.lua`. A release tag must be exactly
  `v<product version>`.
- Never commit license keys, runtime credentials, callback secrets, private
  endpoints, deployment inventories, or customer configuration.
