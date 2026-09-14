
function GetConvar(_name, default) return default end
dofile('config/shared.lua')

local npcPed, partner = 1, 10
local living = { [npcPed] = true, [partner] = true }
local threads, walks, clears, turns, bags, stops = {}, {}, {}, {}, {}, 0
local partnerAt = { x = 5.0, y = 0.0, z = 0.0 }
local taskStatus = 1
local cloudSeconds = 1000
local inVehicle = false
function GetGameTimer() return 1000 end
function GetCloudTimeAsInt() return cloudSeconds end
function GetVehiclePedIsIn() return inVehicle and 30 or 0 end

local mt = {}
mt.__sub = function(a, b)
    return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, mt)
end
mt.__len = function(v) return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z) end
local function at(x, y, z) return setmetatable({ x = x, y = y, z = z }, mt) end

function GetEntityCoords(ped)
    if ped == npcPed then return at(0.0, 0.0, 0.0) end
    return at(partnerAt.x, partnerAt.y, partnerAt.z)
end
function DoesEntityExist(ped) return living[ped] == true end
function GetActivePlayers() return { 110 } end
function GetPlayerPed() return partner end
function GetPlayerFromServerId(serverId) return serverId == 7 and 110 or -1 end
function GetPlayerServerId() return 7 end
function NetworkGetPlayerIndexFromPed() return 110 end
function TaskGoToEntity(ped, target, duration, distance, speed)
    walks[#walks + 1] = { ped = ped, target = target, duration = duration,
        distance = distance, speed = speed }
end
function TaskTurnPedToFaceEntity(ped, target, duration)
    turns[#turns + 1] = { ped = ped, target = target, duration = duration }
end
function ClearPedTasks(ped) clears[#clears + 1] = ped end
function GetScriptTaskStatus() return taskStatus end
function GetHashKey(name) return name end
function CreateThread(fn) threads[#threads + 1] = fn end
function AddStateBagChangeHandler() end
function NetworkHasControlOfEntity() return true end
function IsEntityDead() return false end
function IsPedRagdoll() return false end
function IsPedAPlayer() return false end
function SetBlockingOfNonTemporaryEvents() end
function SetPedKeepTask() end
function BeginStopFollowing(ped)
    stops = stops + 1
    ReleaseActionControl(ped)
end
function Entity(ped)
    return { state = { set = function(_self, key, value) bags[key] = value end } }
end

dofile('client/reactions.lua')
dofile('client/actions/state.lua')
dofile('client/actions/approach_player.lua')

NpcActions['approach_player'](npcPed, { player_id = 7 })
assert(stops == 1, 'approaching ends any follow first')
assert(ActionControlledPeds[npcPed] == 'approach_player', 'the deed owns the ped')
assert(#walks == 1 and walks[1].target == partner and walks[1].speed == 1.0
    and walks[1].distance == Config.Approach.StopRange,
    'a partner a few steps away is walked to')
assert(type(bags['humalike_action']) == 'table'
    and bags['humalike_action'].key == 'approach_player'
    and bags['humalike_action'].params.player_id == 7
    and bags['humalike_action'].params.ends_at == cloudSeconds + 30,
    'the partner and the expiry ride the statebag for the next owner')

taskStatus = 7
NpcActionSustain['approach_player'](npcPed)
assert(#walks == 2 and walks[2].speed == 1.0, 'a dropped walk is re-issued')
taskStatus = 1
NpcActionSustain['approach_player'](npcPed)
assert(#walks == 2, 'a healthy walk is left alone')

partnerAt = { x = 20.0, y = 0.0, z = 0.0 }
NpcActionSustain['approach_player'](npcPed)
assert(#walks == 3 and walks[3].speed == 2.0, 'a partner who moved off is jogged after')
partnerAt = { x = 4.0, y = 0.0, z = 0.0 }
NpcActionSustain['approach_player'](npcPed)
assert(#walks == 4 and walks[4].speed == 1.0, 'and walked to again once close')

partnerAt = { x = 2.0, y = 0.0, z = 0.0 }
NpcActionSustain['approach_player'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'arrival releases the deed to the hold')
assert(#turns == 1 and turns[1].target == partner, 'and the ped turns to face them')
assert(bags['humalike_action'] == nil, 'the statebag is cleared for good')

partnerAt = { x = 1.0, y = 0.0, z = 0.0 }
local walksBefore, turnsBefore = #walks, #turns
NpcActions['approach_player'](npcPed, { player_id = 7 })
assert(ActionControlledPeds[npcPed] == nil and #walks == walksBefore
    and #turns == turnsBefore + 1, 'a partner already beside you is only faced')

partnerAt = { x = 8.0, y = 0.0, z = 0.0 }
NpcActions['approach_player'](npcPed, { player_id = 7 })
assert(ActionControlledPeds[npcPed] == 'approach_player')
cloudSeconds = cloudSeconds + 29
NpcActionSustain['approach_player'](npcPed)
assert(ActionControlledPeds[npcPed] == 'approach_player', 'still walking inside the allowance')
cloudSeconds = cloudSeconds + 2
turnsBefore = #turns
NpcActionSustain['approach_player'](npcPed)
assert(ActionControlledPeds[npcPed] == nil and #turns == turnsBefore,
    'an approach that never arrives is abandoned where it stands')

NpcActions['approach_player'](npcPed, { player_id = 7 })
living[partner] = nil
NpcActionSustain['approach_player'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'a partner who vanished releases the deed')
living[partner] = true

partnerAt = { x = 40.0, y = 0.0, z = 0.0 }
walksBefore = #walks
NpcActions['approach_player'](npcPed, { player_id = 7 })
assert(ActionControlledPeds[npcPed] == nil and #walks == walksBefore,
    'a partner out of reach is not chased')

partnerAt = { x = 8.0, y = 0.0, z = 0.0 }
inVehicle = true
stops = 0
NpcActions['approach_player'](npcPed, { player_id = 7 })
assert(stops == 1 and ActionControlledPeds[npcPed] == nil and #walks == walksBefore,
    'a seated ped only finishes leaving its follow')
inVehicle = false

ActionControlledPeds[npcPed] = 'approach_player'
ActionParams[npcPed] = { player_id = 7, ends_at = cloudSeconds + 5 }
taskStatus = 7
walksBefore = #walks
NpcActionSustain['approach_player'](npcPed)
assert(ActionControlledPeds[npcPed] == 'approach_player' and #walks == walksBefore + 1,
    'an approach resumed by a new owner with time left is re-issued')
ActionControlledPeds[npcPed] = 'approach_player'
ActionParams[npcPed] = { bogus = true }
NpcActionSustain['approach_player'](npcPed)
assert(ActionControlledPeds[npcPed] == nil, 'a partner-less approach is released')

print('approach_player: ok')
