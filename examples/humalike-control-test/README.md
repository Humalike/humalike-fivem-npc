# HumaLike control test

Development-only resource for exercising runtime entity ownership. It is not
included in HumaLike release archives.

Copy or symlink this directory into the FXServer resources directory, then add:

```cfg
add_ace group.admin command.humalike_npc_test allow
ensure humalike
ensure humalike-control-test
```

Use an `external` NPC UUID and its configured model for binding. Use a separate
`static` NPC UUID for despawn and respawn:

```text
/humalike_npc_test bind <npcId> <model>
/humalike_npc_test state <npcId>
/humalike_npc_test unbind <npcId>
/humalike_npc_test despawn <npcId>
/humalike_npc_test respawn <npcId>
/humalike_npc_test delete <npcId>
/humalike_npc_test control <npcId> movement,animation 30000
/humalike_npc_test release <npcId>
```

`unbind` leaves the externally owned test ped in the world. `delete`
deliberately deletes it without unbinding so automatic runtime detachment can
be verified; the external NPC remains offline until it is bound again.
