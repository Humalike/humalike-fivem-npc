-- A retry that overtakes a delivery still waiting on its provider shares the result.
Config = { Integrations = {}, SupportedActions = {}, ServerActions = { MaxDistance = 5.0 } }
NpcRegistry = { ['static-1'] = { npc_id = 'static-1', entity_id = 201 } }

local handle
local runCalls, grant = 0, true
local nextBody

json = { decode = function() return nextBody end, encode = function(value) return value end }
HumaLike = {
    RuntimeCredentials = function()
        return {
            callbackCurrent = { token = 'tok', valid_from_unix = 0, valid_until_unix = 2 ^ 40 },
            callbackNext = { token = 'next', valid_from_unix = 0, valid_until_unix = 2 ^ 40 },
        }
    end,
}
function SetHttpHandler(callback) handle = callback end
local printed = {}
local consolePrint = print
function print(line) printed[#printed + 1] = line end
function HumalikeDebug() end
function GetCurrentResourceName() return 'humalike' end
function AddEventHandler() end
function TriggerEvent() end
function TriggerClientEvent() end
function exports() end
Wait = coroutine.yield
HumalikePlayer = { IsCharacterLoaded = function() return true end }
HumalikeInventory = { Available = function() return true end }
function GetEntityCoords() return { x = 0, y = 0, z = 0 } end
function GetPlayerPed(playerId) return playerId == 7 and 700 or 0 end
function GetPlayerName(playerId) return playerId == 7 and 'Tester' or nil end
function GetPlayerRoutingBucket() return 0 end
function GetEntityRoutingBucket() return 0 end
function DoesEntityExist() return true end
function GetEntityType() return 1 end
function IsPedAPlayer() return false end
function GetEntityHealth() return 100 end
function RecordNpcPose() end

dofile('../server/core/text.lua')
dofile('../server/core/callbacks.lua')
dofile('../integration/server/registry.lua')
dofile('../integration/server/actions.lua')
assert(HumalikeRegisterInternalProvider('actions', {
    name = 'srp_actions', apiVersion = 1, priority = 10, SupportedActions = {}, Namespace = 'srp',
    Actions = { give_map = { name = 'Give the map', description = 'Hand over the map.' } },
    RunAction = function()
        runCalls = runCalls + 1
        coroutine.yield()
        return grant
    end,
}))
dofile('server/inbound.lua')

-- Each call runs as its own scheduler thread; resume() advances it one yield.
local function post(requestId, invocationId)
    local body = {
        request_id = requestId, invocation_id = invocationId,
        target = { kind = 'static', npc_id = 'static-1' }, action = 'srp:give_map',
        params = { player_id = 7 },
    }
    local call = {}
    local thread = coroutine.create(function()
        nextBody = body
        handle({
            path = '/action', method = 'POST', headers = { authorization = 'Bearer tok' },
            setDataHandler = function(onBody) onBody('{}') end,
        }, {
            writeHead = function(status) call.status = status end,
            send = function(answer) call.body = answer end,
        })
    end)
    function call.resume()
        local ok, err = coroutine.resume(thread)
        assert(ok, err)
        return coroutine.status(thread) == 'dead'
    end
    return call
end

local first = post('req-1', 'inv-1')
assert(not first.resume(), 'the provider is waiting')
local retry = post('req-1', 'inv-1')
assert(not retry.resume(), 'the retry waits on the pending delivery')
assert(runCalls == 1, 'the retry must not run the provider again')
assert(first.resume() and first.status == 200 and first.body.ok == true)
assert(retry.resume() and retry.status == 200 and retry.body.ok == true)
assert(runCalls == 1)
local again = post('req-1', 'inv-1')
assert(again.resume() and again.body.ok == true and runCalls == 1, 'answered from the cache')

-- A refusal shared by both releases the id, so an intended retry runs again.
grant = false
first = post('req-2', 'inv-2')
assert(not first.resume())
retry = post('req-2', 'inv-2')
assert(not retry.resume())
assert(first.resume() and first.body.ok == false and first.body.reason == 'action_rejected')
assert(retry.resume() and retry.body.ok == false and retry.body.reason == 'action_rejected')
assert(runCalls == 2)
grant = true
again = post('req-2', 'inv-2')
assert(not again.resume())
assert(again.resume() and again.body.ok == true and runCalls == 3)

consolePrint('server_inbound_retry: ok')
