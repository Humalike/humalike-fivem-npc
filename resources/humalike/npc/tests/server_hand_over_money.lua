
Config = { Robbery = { MaxDistance = 5.0 } }

local handler
local handOverCalls = {}
local playerName = 'Tester'
local characterLoaded = true
local pedExists = true
local pedCoords = { x = 0, y = 0, z = 0 }

function AddEventHandler(name, fn)
    if name == 'humalike:npc:runHandOverMoneyAction' then handler = fn end
end
function HumalikeDebug() end
function GetPlayerName() return playerName end
function GetPlayerPed() return 55 end
function DoesEntityExist() return pedExists end
function GetEntityCoords() return pedCoords end

HumalikePlayer = {
    IsCharacterLoaded = function() return characterLoaded end,
}
HumalikeActions = {
    Run = function(action, source, coords, params)
        assert(action == 'hand_over_money')
        handOverCalls[#handOverCalls + 1] = {
            source = source, coords = coords, desc = params.robber_description,
        }
        return true
    end,
}

dofile('server/actions/hand_over_money.lua')
assert(handler, 'handler registered')

local function invoke(npcCoords, params)
    local result
    handler(npcCoords, params, function(r) result = r end)
    return result
end

local npc = { x = 0, y = 0, z = 0 }
assert(invoke(npc, { player_id = 7, robber_description = 'czarna kominiarka' }) == true)
assert(#handOverCalls == 1)
assert(handOverCalls[1].source == 7)
assert(handOverCalls[1].desc == 'czarna kominiarka')
assert(invoke(npc, {}) == false)
assert(invoke(npc, { player_id = 0 }) == false)
assert(invoke(npc, { player_id = 1.5 }) == false)
assert(#handOverCalls == 1, 'no bridge call on invalid params')
assert(invoke(npc, { player_id = 7, robber_description = 123 }) == true)
assert(handOverCalls[#handOverCalls].desc == nil)
pedCoords = { x = 100, y = 0, z = 0 }
local before = #handOverCalls
assert(invoke(npc, { player_id = 7 }) == false)
assert(#handOverCalls == before, 'no payout when the player is too far')
pedCoords = { x = 0, y = 0, z = 0 }
characterLoaded = false
assert(invoke(npc, { player_id = 7 }) == false)
characterLoaded = true
pedExists = false
assert(invoke(npc, { player_id = 7 }) == false)
pedExists = true
HumalikeActions.Run = function() return false end
assert(invoke(npc, { player_id = 7 }) == false)

print('server_hand_over_money: ok')
