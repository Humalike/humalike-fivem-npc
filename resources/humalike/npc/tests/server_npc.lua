local events = {}
local bindingRepairs = {}
function EnsurePersistentNpc(entry, repairBinding)
    bindingRepairs[#bindingRepairs + 1] = repairBinding == true
    entry.network_id = 100
    return 1
end
function RemovePersistentNpc(_) end
local response = 0

function TriggerClientEvent(name, _, payload)
    events[#events + 1] = { name = name, payload = payload }
end
function HumalikeDebug() end

HumalikeHttp = {
    PostAction = function(action, request, callback)
        assert(action == 'get_npc_roster')
        assert(next(request) == nil)
        response = response + 1
        callback(true, 200, {
            npcs = {
                {
                    npc_id = 'static-1',
                    name = 'Jan',
                    x = 1,
                    y = 2,
                    z = 3,
                    heading = 90,
                    model = 'a_m_m_business_01',
                    language = response >= 3 and 'en' or 'pl',
                    voice_muted = response >= 2,
                },
            },
        })
    end,
}
function CreateThread() end
function Wait() end

dofile('server/pose_ledger.lua') -- loaded before npc.lua by the manifest
dofile('server/npc.lua')
SyncNpcRoster()
SyncNpcRoster()
SyncNpcRoster()

assert(#events == 3)
assert(events[1].name == 'humalike:npc:npcAdded')
assert(events[1].payload.voice_muted == false)
assert(events[2].name == 'humalike:npc:npcAdded')
assert(events[2].payload.voice_muted == true)
assert(events[3].name == 'humalike:npc:npcAdded')
assert(events[3].payload.language == 'en')
assert(NpcRegistry['static-1'].voice_muted == true)
assert(NpcRegistry['static-1'].language == 'en')
assert(bindingRepairs[1] == false and bindingRepairs[2] == false and bindingRepairs[3] == false)

SyncNpcRoster(nil, true)
assert(bindingRepairs[4] == true)
