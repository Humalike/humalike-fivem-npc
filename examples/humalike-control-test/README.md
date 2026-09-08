# HumaLike control test

Development-only NPC panel for external body lifecycle, runtime control and
teleporting to external, static and dynamic NPCs.
It is not included in HumaLike release archives.

## Install and open

Use a HumaLike resource version that exposes `ListNpcRuntimeStates` in addition
to the entity-binding and runtime-control exports. An older version produces
`humalike_unavailable_or_outdated` in the panel.

Copy or symlink **this example directory only** into the FXServer resources
directory, then configure:

```cfg
add_ace group.admin command.humalike_npc_test allow
ensure humalike
ensure humalike-control-test
```

Press **F7**, or run `/humalike_npc_test` in chat. F7 can be rebound under FiveM
key bindings. Close with Escape or the Close button. Access is checked on the
server for every read and operation, including requests submitted without the UI.

## Panel

External and Static list the current synced FiveM roster, including NPCs with
no bound ped. Dynamic lists current server ambient AI leases, not player
encounter history or every world ped. Dynamic rows use the NPC ID and model
hash because the lease list does not expose character display names.

Search by name, model or UUID; filter bound/offline/test peds. The panel shows
binding state, AI control domains, network ID, routing bucket and owning
resource. It checks for updates every two seconds while open, preserving
unchanged rows and buttons. Actions only disable the affected NPC controls; clicks during refresh
are queued.

- **Teleport:** moves your on-foot character next to an existing NPC ped, including
  static NPCs and bodies owned by other resources. It also follows the NPC routing
  bucket. Missing or stale entities are rejected on the server.
- **Spawn & bind / Respawn here (External):** creates the configured model beside your
  character in your routing bucket and binds it. Respawn removes the previous
  test body first. The model and NPC identity come from the server roster.
- **Unbind:** detaches the identity but leaves the test ped in the world.
- **Delete ped:** removes the body without unbinding first, exercising automatic
  detachment. A confirmation protects against accidental clicks. This does not
  delete the NPC definition in the dashboard.
- **Control 30s:** temporarily takes over movement and animation.
- **Release:** releases control acquired by this test resource.

Only peds created by this resource can be modified through the panel; teleport
only moves the player. Bodies owned by other integrations are visible but protected. Existing test peds must
be within 50 metres and in the same routing bucket before they are modified.
Stopping the test resource removes its peds and releases its control. Restarting
HumaLike rebinds surviving test peds after its roster becomes ready.

The roster is supplied by HumaLike, not queried directly from the dashboard.
Disabled or not-yet-synced definitions may be absent. Enable the external NPC in
the dashboard and wait for roster sync before spawning it. Empty lists and
missing/incompatible HumaLike exports are reported separately. These statuses
refer to the local FiveM runtime, not a guarantee of a working audio connection.

## Existing commands

Use an `external` UUID and its configured model for binding. Use a separate
`static` UUID for despawn and respawn:

```text
/humalike_npc_test bind <npcId> <model>
/humalike_npc_test state <npcId>
/humalike_npc_test unbind <npcId>
/humalike_npc_test delete <npcId>
/humalike_npc_test control <npcId> movement,animation 30000
/humalike_npc_test release <npcId>
/humalike_npc_test despawn <npcId>
/humalike_npc_test respawn <npcId>
```

## Checks

Run from the repository root:

```sh
lua examples/humalike-control-test/tests/server.lua
lua examples/humalike-control-test/tests/client.lua
node --check examples/humalike-control-test/web/app.js
node examples/humalike-control-test/tests/web.cjs
```

In FiveM, verify F7 access as an admin and denial as an unprivileged player,
spawn/unbind/respawn/delete, lease expiry, another routing bucket, HumaLike restart,
and test-resource stop. The Lua tests simulate the FiveM host boundary; they do
not replace an in-game smoke test of entity replication and NUI focus.
