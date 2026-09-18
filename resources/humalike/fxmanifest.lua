fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'humalike'
author 'HumaLike'
description 'Unified HumaLike NPC, world-state and voice runtime'
version '0.4.0'

ui_page 'nui/host/dist/index.html'

files {
    'nui/host/dist/index.html',
    'nui/host/dist/assets/*',
    'nui/host/dist/audio/*'
}

shared_scripts {
    'world/config.lua',
    'npc/config/shared.lua',
    'npc/config/wounds.lua'
}

server_scripts {
    'server/core/status.lua',
    'server/core/retries.lua',
    'server/core/export_result.lua',
    'server/core/credentials.lua',
    'server/core/http.lua',
    'server/core/callbacks.lua',
    'server/core/bootstrap.lua',
    'world/server/contracts.lua',
    'world/server/authority.lua',
    'world/server/npc_edge.lua',
    'world/server/voice.lua',
    'world/server/cabins.lua',
    'world/server/main.lua',
    'integration/server/registry.lua',
    'integration/server/player.lua',
    'integration/server/inventory.lua',
    'integration/server/dispatch.lua',
    'integration/server/actions.lua',
    'integration/providers/common/server.lua',
    'integration/providers/standalone/server.lua',
    'integration/providers/esx/server.lua',
    'integration/providers/qbcore/server.lua',
    'integration/providers/qbox/server.lua',
    'integration/providers/ox_inventory/server.lua',
    'integration/providers/qb_inventory/server.lua',
    'npc/server/http.lua',
    'npc/server/runtime_state.lua',
    'npc/server/pose_ledger.lua',
    'npc/server/pose_threat.lua',
    'npc/server/entity_ownership.lua',
    'npc/server/persistent.lua',
    'npc/server/npc.lua',
    'npc/server/sessions.lua',
    'npc/server/ambient.lua',
    'npc/server/population.lua',
    'npc/server/runtime_control.lua',
    'npc/server/developer_tools.lua',
    'npc/server/wounded.lua',
    'npc/server/wounds.lua',
    'npc/server/world_events.lua',
    'npc/server/observations.lua',
    'integration/providers/esx/world_events.lua',
    'integration/providers/qbcore/world_events.lua',
    'integration/providers/qbox/world_events.lua',
    'npc/server/weapon_state.lua',
    'npc/server/vehicle_damage.lua',
    'npc/server/actions/give_item.lua',
    'npc/server/actions/hand_over_money.lua',
    'npc/server/inbound.lua',
    'npc/server/main.lua',
    'voice/server/main.lua'
}

client_scripts {
    'integration/client/interactions.lua',
    'integration/providers/esx/world_events_client.lua',
    'integration/providers/builtin/client.lua',
    'integration/providers/ox_target/client.lua',
    'integration/providers/qb_target/client.lua',
    'world/client/contracts.lua',
    'world/client/registry.lua',
    'world/client/vehicle.lua',
    'world/client/cabins.lua',
    'world/client/collector.lua',
    'world/client/npc_edge.lua',
    'world/client/main.lua',
    'npc/client/style.lua',
    'npc/client/reactions.lua',
    'npc/client/persistent_control.lua',
    'npc/client/actions/state.lua',
    'npc/client/actions/wave.lua',
    'npc/client/actions/start_dancing.lua',
    'npc/client/actions/interrupt_animation.lua',
    'npc/client/actions/kneel.lua',
    'npc/client/actions/hands_up.lua',
    'npc/client/actions/punch.lua',
    'npc/client/actions/stand_up.lua',
    'npc/client/actions/enter_vehicle.lua',
    'npc/client/actions/enter_own_vehicle.lua',
    'npc/client/actions/exit_vehicle.lua',
    'npc/client/actions/follow_player.lua',
    'npc/client/actions/stop_following.lua',
    'npc/client/actions/leave.lua',
    'npc/client/actions/walk_away.lua',
    'npc/client/actions/run_away.lua',
    'npc/client/actions/hold_position.lua',
    'npc/client/actions/release_movement.lua',
    'npc/client/actions/hand_over_money.lua',
    'npc/client/weapon_state.lua',
    'npc/client/vehicle_damage.lua',
    'npc/client/appearance.lua',
    'npc/client/wounded.lua',
    'npc/client/wound_card.lua',
    'npc/client/combat.lua',
    'npc/client/shove.lua',
    'npc/client/main.lua',
    'npc/client/voice_animation.lua',
    'npc/client/world.lua',
    'npc/client/ambient_control.lua',
    'npc/client/ambient.lua',
    'npc/client/driving.lua',
    'npc/client/population.lua',
    'npc/client/developer_tools.lua',
    'npc/client/runtime_control.lua',
    'npc/client/direct_targets.lua',
    'npc/client/labels.lua',
    'voice/client/ptt.lua',
    'voice/client/main.lua'
}
