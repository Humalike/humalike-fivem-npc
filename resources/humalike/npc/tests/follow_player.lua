Config = {
    ActionSustainTickMs = 250,
    Follow = {
        MaxDistance = 6.0,
        OffsetBehind = -1.5,
        StoppingRange = 2.0,
        RunBehindDistance = 8.0,
        SprintBehindDistance = 15.0,
        RunSpeedThreshold = 3.0,
        SprintSpeedThreshold = 6.2,
        VehicleTaskTimeoutMs = 10000,
        VehicleRetryMs = 1500,
        VehicleEntrySpeed = 2.0,
    },
}

local partner, vehicle = 10, 20
local living = { [1] = true, [2] = true, [3] = true, [partner] = true, [vehicle] = true }
local threads, bagHandler = {}, nil
local bags, follows, enters, leaves, clears = {}, {}, {}, {}, {}
local keepTask, blocking = {}, {}
local inVehicle = {}
local occupied = { [vehicle] = {} }
local locks = { [vehicle] = 1 }
local maxPassengers = { [vehicle] = 2 }
local gameTimer, followTaskStatus, leaveTaskStatus = 0, 1, 7
local partnerSpeed, partnerX = 0.0, 1.0

local mt = {
    __sub = function(a, b) return setmetatable({ x = a.x - b.x }, getmetatable(a)) end,
    __len = function(v) return math.abs(v.x) end,
}
local function at(x) return setmetatable({ x = x }, mt) end

function GetEntityCoords(ped) return ped == partner and at(partnerX) or at(0.0) end
function DoesEntityExist(entity) return living[entity] == true end
function GetEntitySpeed() return partnerSpeed end
function GetActivePlayers() return { 110 } end
function GetPlayerPed() return partner end
function GetPlayerFromServerId(serverId) return serverId == 7 and 110 or -1 end
function GetPlayerServerId() return 7 end
function NetworkGetPlayerIndexFromPed() return 110 end
function GetGameTimer() return gameTimer end
function GetVehiclePedIsIn(ped) return inVehicle[ped] or 0 end
function NetworkGetNetworkIdFromEntity(entity) return entity + 1000 end
function GetVehicleMaxNumberOfPassengers(entity) return maxPassengers[entity] or 0 end
function IsVehicleSeatFree(entity, seat)
    return occupied[entity] and occupied[entity][seat] == nil
end
function GetVehicleDoorLockStatus(entity) return locks[entity] or 1 end
function TaskFollowToOffsetOfEntity(ped, target, _x, _y, _z, gait)
    follows[#follows + 1] = { ped = ped, target = target, gait = gait }
    followTaskStatus = 1
end
function TaskEnterVehicle(ped, targetVehicle, timeout, seat, speed, flag)
    enters[#enters + 1] = { ped = ped, vehicle = targetVehicle, timeout = timeout,
        seat = seat, speed = speed, flag = flag }
end
function TaskLeaveVehicle(ped, targetVehicle, flag)
    leaves[#leaves + 1] = { ped = ped, vehicle = targetVehicle, flag = flag }
    leaveTaskStatus = 1
end
function ClearPedTasks(ped)
    clears[#clears + 1] = ped
    followTaskStatus, leaveTaskStatus = 7, 7
end
function GetScriptTaskStatus(_ped, taskHash)
    return taskHash == 'SCRIPT_TASK_LEAVE_VEHICLE' and leaveTaskStatus or followTaskStatus
end
function GetHashKey(name) return name end
function CreateThread(fn) threads[#threads + 1] = fn end
function AddStateBagChangeHandler(_key, _filter, fn) bagHandler = fn end
function GetEntityFromStateBagName(name) return tonumber(name:match('entity:(%d+)')) or 0 end
function IsPedAPlayer() return false end
function NetworkHasControlOfEntity() return true end
function IsEntityDead() return false end
function IsPedRagdoll() return false end
function SetBlockingOfNonTemporaryEvents(ped, value) blocking[ped] = value end
function SetPedKeepTask(ped, value) keepTask[ped] = value end
local populationPeds = {}
function Entity(ped)
    return { state = {
        set = function(_self, key, value) bags[ped .. key] = value end,
        humalike_npc_kind = populationPeds[ped] and 'population' or nil,
    } }
end

local sustainThread
local function loadClient()
    threads = {}
    HumalikeNpcDriving = HumalikeNpcDriving or { DrivesOwnVehicle = function() return false end }
NpcActionDrivesOwnVehicle = NpcActionDrivesOwnVehicle or function() return false end
dofile('client/reactions.lua')
    dofile('client/actions/state.lua')
    dofile('client/actions/follow_player.lua')
    dofile('client/actions/stop_following.lua')
    sustainThread = threads[1]
    assert(sustainThread and bagHandler)
end

local function tick(count)
    local remaining = count or 1
    Wait = function()
        remaining = remaining - 1
        if remaining < 0 then error('done', 0) end
    end
    pcall(sustainThread)
end

loadClient()
NpcActionSustain.hands_up = function() end
MarkActionControl(1, 'hands_up', {})
bagHandler('entity:1', 'humalike_action', nil)
assert(ActionControlledPeds[1] == nil and keepTask[1] == false and blocking[1] == false,
    'clearing replicated action state stops local sustain without clearing native tasks')
populationPeds[1] = true
HumalikeNpcPopulationClient = {
    OwnsReactions = function(ped) return populationPeds[ped] == true end,
    OwnPace = function() end,
    RestorePace = function() end,
}
MarkActionControl(1, 'hands_up', {})
bagHandler('entity:1', 'humalike_action', nil)
assert(ActionControlledPeds[1] == nil and keepTask[1] == false and blocking[1] == true,
    'a population body stays blocked when replicated state clears')
MarkActionControl(1, 'hands_up', {})
ReleaseActionControl(1)
assert(ActionControlledPeds[1] == nil and keepTask[1] == false and blocking[1] == true,
    'a population body stays blocked after a local release')
populationPeds[1] = nil
MarkActionControl(1, 'hands_up', {})
ReleaseActionControl(1)
assert(blocking[1] == false, 'any other ped gets its reactions back on release')
HumalikeNpcPopulationClient = nil
MarkActionControl(1, 'hands_up', {})
local clearsBeforeFollow = #clears
NpcActions.follow_player(1, { player_id = 7 })
assert(#clears == clearsBeforeFollow + 1, 'follow clears the previous held pose')
assert(#follows == 1 and follows[1].ped == 1 and follows[1].gait == 1.0)
assert(ActionControlledPeds[1] == 'follow_player')
assert(bags['1humalike_action'].params.player_id == 7)
tick(1)
assert(#follows == 1, 'a healthy walking task is not spammed')
partnerSpeed = 5.0
tick(1)
assert(#follows == 2 and follows[2].gait == 2.0)
followTaskStatus = 7
tick(1)
assert(#follows == 3 and follows[3].gait == 2.0)
followTaskStatus = 1
partnerSpeed, partnerX = 0.0, 16.0
tick(1)
assert(#follows == 4 and follows[4].gait == 3.0)
partnerX = 1.0
tick(1)
assert(#follows == 5 and follows[5].gait == 1.0)
inVehicle[partner] = vehicle
tick(1)
assert(#enters == 1 and enters[1].ped == 1 and enters[1].seat == 1)
assert(enters[1].timeout == 10000 and enters[1].flag == 1)
ActionControlledPeds[1], ActionParams[1] = nil, nil -- another owner's empty view
NpcActions.follow_player(2, { player_id = 7 })
assert(#enters == 2 and enters[2].ped == 2 and enters[2].seat == 0)
assert(ActionParams[2].passenger_seat == 0)
for _, entry in ipairs(enters) do assert(entry.seat >= 0, 'driver seat must never be selected') end
assert(inVehicle[1] == nil and inVehicle[2] == nil, 'TaskEnterVehicle must not warp')
local singleSeatVehicle = 22
living[singleSeatVehicle] = true
occupied[singleSeatVehicle] = {}
locks[singleSeatVehicle] = 1
maxPassengers[singleSeatVehicle] = 1
inVehicle[partner] = singleSeatVehicle
ActionControlledPeds[2], ActionParams[2] = nil, nil
local beforeSingleSeat = #enters
NpcActions.follow_player(1, { player_id = 7 })
ActionControlledPeds[1], ActionParams[1] = nil, nil
NpcActions.follow_player(2, { player_id = 7 })
assert(enters[beforeSingleSeat + 1].seat == 0 and enters[beforeSingleSeat + 2].seat == 0)
gameTimer = 10000
tick(1)
assert(#enters == beforeSingleSeat + 2)
gameTimer = 11500
tick(1)
assert(#enters == beforeSingleSeat + 3 and enters[#enters].ped == 2)
while #enters > beforeSingleSeat do enters[#enters] = nil end
ActionControlledPeds[2], ActionParams[2] = nil, nil
inVehicle[partner] = vehicle
gameTimer = 0
occupied[vehicle][0] = 90
occupied[vehicle][1] = 91
NpcActions.follow_player(3, { player_id = 7 })
assert(#enters == 2, 'full vehicles must not evict or create an entry task')
gameTimer = 1000
tick(1)
assert(#enters == 2)
occupied[vehicle][0] = nil
gameTimer = 1499
tick(1)
assert(#enters == 2)
gameTimer = 1500
tick(1)
assert(#enters == 3 and enters[3].ped == 3 and enters[3].seat == 0)
local beforeRetry = #enters
gameTimer = 11499
tick(1)
assert(#enters == beforeRetry)
gameTimer = 11500
tick(1)
assert(#enters == beforeRetry, 'timeout moves to cooldown without immediate spam')
gameTimer = 12999
tick(1)
assert(#enters == beforeRetry)
gameTimer = 13000
tick(1)
assert(#enters == beforeRetry + 1)
ActionControlledPeds[3] = nil
ActionParams[3] = nil
locks[vehicle] = 2
gameTimer = 20000
NpcActions.follow_player(1, { player_id = 7 })
assert(#enters == beforeRetry + 1)
gameTimer = 21499
tick(1)
assert(#enters == beforeRetry + 1)
locks[vehicle] = 1
gameTimer = 21500
tick(1)
assert(#enters == beforeRetry + 2)
inVehicle[1] = vehicle
occupied[vehicle][0] = 1
local ridingEntries = #enters
local clearsBeforeSeatedFollow = #clears
NpcActions.follow_player(1, { player_id = 7 })
assert(#clears == clearsBeforeSeatedFollow, 'follow never clears a passenger seat task')
tick(2)
assert(#enters == ridingEntries)
inVehicle[partner] = nil
tick(1)
assert(#leaves == 1 and leaves[1].ped == 1 and leaves[1].vehicle == vehicle)
tick(2)
assert(#leaves == 1, 'leave task is not spammed before its timeout')
inVehicle[1] = nil
occupied[vehicle][0] = nil
local clearsBeforeTailStop = #clears
NpcActions.stop_following(1, {})
assert(ActionControlledPeds[1] == 'stop_following')
tick(1)
assert(ActionControlledPeds[1] == 'stop_following' and #clears == clearsBeforeTailStop,
    'a stop command preserves the active zero-occupancy leave tail')
leaveTaskStatus = 7
tick(1)
assert(ActionControlledPeds[1] == nil and #clears == clearsBeforeTailStop + 1)
inVehicle[partner], inVehicle[1] = vehicle, vehicle
occupied[vehicle][0] = 1
NpcActions.follow_player(1, { player_id = 7 })
inVehicle[partner] = nil
tick(1)
inVehicle[1] = nil
occupied[vehicle][0] = nil
local followsBeforeResume = #follows
tick(1)
assert(#follows == followsBeforeResume and ActionControlledPeds[1] == 'follow_player')
leaveTaskStatus = 7
tick(1)
assert(#follows == followsBeforeResume + 1 and follows[#follows].ped == 1,
    'on-foot follow resumes after the leave task finishes')
local vehicle2 = 21
living[vehicle2] = true
occupied[vehicle2] = {}
locks[vehicle2] = 1
maxPassengers[vehicle2] = 1
inVehicle[partner] = vehicle
inVehicle[1] = vehicle
occupied[vehicle][0] = 1
tick(1)
inVehicle[partner] = vehicle2
tick(1)
assert(leaves[#leaves].vehicle == vehicle)
inVehicle[1] = nil
occupied[vehicle][0] = nil
local entriesBeforeSwitchCompletion = #enters
tick(1)
assert(#enters == entriesBeforeSwitchCompletion, 'switch waits for active leave completion')
leaveTaskStatus = 7
tick(1)
assert(enters[#enters].vehicle == vehicle2 and enters[#enters].seat == 0)
inVehicle[1] = vehicle2
occupied[vehicle2][0] = 1
NpcActions.stop_following(1, {})
assert(ActionControlledPeds[1] == 'stop_following')
assert(bags['1humalike_action'].key == 'stop_following')
assert(leaves[#leaves].ped == 1)
tick(2)
assert(ActionControlledPeds[1] == 'stop_following')
inVehicle[1] = nil
occupied[vehicle2][0] = nil
local clearsBeforeStopCompletion = #clears
tick(1)
assert(ActionControlledPeds[1] == 'stop_following')
assert(#clears == clearsBeforeStopCompletion, 'active leave is not cleared at zero occupancy')
leaveTaskStatus = 7
tick(1)
assert(ActionControlledPeds[1] == nil and bags['1humalike_action'] == nil)
assert(#clears == clearsBeforeStopCompletion + 1)
living[partner] = true
inVehicle[partner], inVehicle[2] = vehicle, vehicle
occupied[vehicle][1] = 2
NpcActions.follow_player(2, { player_id = 7 })
inVehicle[partner] = nil
tick(1)
inVehicle[2] = nil
occupied[vehicle][1] = nil
local clearsBeforeTailLoss = #clears
living[partner] = false
tick(1)
assert(ActionControlledPeds[2] == 'stop_following' and #clears == clearsBeforeTailLoss)
leaveTaskStatus = 7
tick(1)
assert(ActionControlledPeds[2] == nil and #clears == clearsBeforeTailLoss + 1)
living[partner] = true
inVehicle[partner] = vehicle
inVehicle[2] = vehicle
occupied[vehicle][1] = 2
NpcActions.follow_player(2, { player_id = 7 })
local adopted = bags['2humalike_action']
assert(adopted and adopted.key == 'follow_player')
loadClient()
bagHandler('entity:2', 'humalike_action', adopted)
local beforeAdoption = #enters
tick(1)
assert(ActionControlledPeds[2] == 'follow_player')
assert(#enters == beforeAdoption, 'an adopted rider is not told to enter again')
living[partner] = false
tick(1)
assert(ActionControlledPeds[2] == 'stop_following')
assert(leaves[#leaves].ped == 2)
local adoptedStop = bags['2humalike_action']
assert(adoptedStop and adoptedStop.key == 'stop_following')
loadClient()
bagHandler('entity:2', 'humalike_action', adoptedStop)
local leavesBeforeStopAdoption = #leaves
tick(1)
assert(#leaves == leavesBeforeStopAdoption + 1, 'the new owner resumes leaving')
assert(ActionControlledPeds[2] == 'stop_following')
inVehicle[2] = nil
occupied[vehicle][1] = nil
tick(1)
assert(ActionControlledPeds[2] == 'stop_following')
leaveTaskStatus = 7
tick(1)
assert(ActionControlledPeds[2] == nil and bags['2humalike_action'] == nil)
living[partner] = true
inVehicle[partner] = nil
NpcActions.follow_player(3, { player_id = 7 })
assert(ActionControlledPeds[3] == 'follow_player')
living[partner] = false
tick(1)
assert(ActionControlledPeds[3] == nil)
living[partner] = true
inVehicle[partner] = vehicle
occupied[vehicle][0], occupied[vehicle][1] = nil, nil
NpcActions.follow_player(3, { player_id = 7 })
assert(ActionParams[3].passenger_seat ~= nil)
local clearsBeforeMissingEntry = #clears
living[partner] = false
tick(1)
assert(ActionControlledPeds[3] == nil and ActionParams[3] == nil)
assert(#clears == clearsBeforeMissingEntry + 1)
living[partner] = true
inVehicle[partner] = nil
NpcActions.follow_player(3, { player_id = 7 })
local followsBeforeSupersede = #follows
NpcActionSustain.kneel = function() end
MarkActionControl(3, 'kneel', {})
tick(2)
assert(#follows == followsBeforeSupersede)
assert(ActionControlledPeds[3] == 'kneel')

print('follow_player: ok')
