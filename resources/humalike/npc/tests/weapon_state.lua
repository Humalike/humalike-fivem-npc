local hashes = {
    WEAPON_UNARMED = 0,
    WEAPON_PISTOL = 10,
    WEAPON_CARBINERIFLE = 2210333304,
    WEAPON_BATTLERIFLE = 30,
}
local weapons = { 0, 10, 10, -2084633992, 0, 30 }
local sent = {}
local thread
local index = 0

function GetHashKey(name)
    if hashes[name] then return hashes[name] end
    return 1000 + #name
end

function CreateThread(callback) thread = callback end

function Wait()
    index = index + 1
    if index > #weapons then error('done') end
end

function PlayerPedId() return 1 end
function DoesEntityExist() return true end
function GetSelectedPedWeapon() return weapons[index] end

function TriggerServerEvent(_, eventType, previousWeapon, weapon, previousName, weaponName)
    sent[#sent + 1] = { eventType, previousWeapon, weapon, previousName, weaponName }
end

dofile('client/weapon_state.lua')
pcall(thread)

assert(#sent == 3) -- initial sync, pistol -> pistol and pistol -> carbine emit nothing
assert(sent[1][1] == 'weapon_drawn' and sent[1][4] == 'WEAPON_UNARMED'
    and sent[1][5] == 'WEAPON_PISTOL')
assert(sent[2][1] == 'weapon_holstered' and sent[2][4] == 'WEAPON_CARBINERIFLE'
    and sent[2][5] == 'WEAPON_UNARMED')
assert(sent[3][1] == 'weapon_drawn' and sent[3][5] == 'WEAPON_BATTLERIFLE')
