
local peds = {} -- ped handle -> { coords, server_id }
local npcPed = 1

local function at(x) return { x = x, y = 0.0, z = 0.0 } end

peds[npcPed] = { coords = at(0.0) }
peds[10] = { coords = at(2.0), server_id = 7 } -- the partner, 2 m away
peds[11] = { coords = at(1.0), server_id = 9 } -- a bystander, closer
peds[12] = { coords = at(50.0), server_id = 13 } -- far away

function GetEntityCoords(ped) return peds[ped].coords end
function DoesEntityExist(ped) return peds[ped] ~= nil end
function GetActivePlayers() return { 110, 111, 112 } end
function GetPlayerPed(playerId)
    return ({ [110] = 10, [111] = 11, [112] = 12 })[playerId] or 0
end
function GetPlayerFromServerId(serverId)
    for playerId, ped in pairs({ [110] = 10, [111] = 11, [112] = 12 }) do
        if peds[ped].server_id == serverId then return playerId end
    end
    return -1
end
local mt = {
    __sub = function(a, b) return setmetatable({ x = a.x - b.x }, getmetatable(a)) end,
    __len = function(v) return math.abs(v.x) end,
}
for _, entry in pairs(peds) do setmetatable(entry.coords, mt) end

function CreateThread() end
function AddStateBagChangeHandler() end

dofile('client/reactions.lua')
dofile('client/actions/state.lua')
assert(ActionTargetPed(npcPed, { player_id = 7 }, 4.0) == 10)
assert(ActionTargetPed(npcPed, {}, 4.0) == 11)
assert(ActionTargetPed(npcPed, nil, 4.0) == 11)
assert(ActionTargetPed(npcPed, { player_id = 13 }, 4.0) == nil)
assert(ActionTargetPed(npcPed, { player_id = 13 }, 4.0) ~= 11)
assert(ActionTargetPed(npcPed, { player_id = 999 }, 4.0) == nil)
assert(ActionTargetPed(npcPed, { player_id = '7' }, 4.0) == 11)
assert(ActionTargetPed(npcPed, { player_id = 13 }, 60.0) == 12)

print('action_target: ok')
