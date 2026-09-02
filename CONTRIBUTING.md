# Contributing to HumaLike for FiveM

We welcome focused pull requests that make the resource more reliable, easier
to integrate, or better documented. Bug fixes, tests, performance improvements,
generic framework providers, and documentation corrections are especially
useful.

## Discuss larger changes first

Open a discussion on the [HumaLike Discord](https://discord.gg/7bZFjm9aHH)
before implementing a change that:

- adds a user-facing feature or configuration option;
- changes NPC, voice, world, or integration behavior;
- adds or changes a provider domain or public capability;
- changes communication between the FiveM resource and HumaLike;
- changes a public export, event, convar, command, or data contract;
- adds a dependency or changes release packaging.

Early discussion lets us agree on the contract and avoid asking you to rewrite
a completed contribution. Small bug fixes, tests, and documentation corrections
can go directly to a pull request.

## Compatibility boundaries

Do not independently change the resource-to-HumaLike wire contract,
authentication or licensing flow, runtime credential handling, service
addresses, or protocol payloads. These changes require a coordinated HumaLike
release and prior maintainer approval.

Treat the versioned provider APIs, public exports, events, convars, and commands
as compatibility contracts. Additive changes still need discussion; breaking
changes require an explicit migration plan and coordinated release.

Keep the core resource standalone and framework-neutral. Server-specific jobs,
economy rules, permissions, private events, and UI hooks belong in a separate
adapter resource. Generic integrations must use a dependency's public API and
must remain optional.

Do not commit credentials, license keys, private endpoints, customer names,
deployment details, or generated runtime data.

## Pull request workflow

1. Branch from the current `main`.
2. Keep the pull request focused on one behavior or contract.
3. Add or update focused tests for behavior changes.
4. Update public documentation when the supported public surface changes.
5. Explain the motivation, compatibility impact, and validation in the pull
   request description.

Run the relevant checks before opening the pull request:

```sh
pnpm --dir resources/humalike install --frozen-lockfile
pnpm --dir resources/humalike check
pnpm --dir resources/humalike test:unit
pnpm --dir resources/humalike build
python3 -m unittest discover -s tests -v
python3 scripts/audit_public_release.py
```

If the NUI changes, rebuild it and commit the generated
`resources/humalike/nui/host/dist` output. Do not edit generated files by hand.

Maintainers may ask to split a broad pull request or adjust its design to keep
the public contracts stable. Acceptance of a proposal or pull request is not
guaranteed.

## Security issues

Do not disclose vulnerabilities in a public issue or on Discord. Use
[GitHub private vulnerability reporting](https://github.com/Humalike/humalike-fivem-npc/security/advisories/new).

