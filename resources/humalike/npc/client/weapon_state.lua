local weaponNames = {
    'WEAPON_UNARMED', 'WEAPON_KNIFE', 'WEAPON_NIGHTSTICK', 'WEAPON_HAMMER',
    'WEAPON_BAT', 'WEAPON_GOLFCLUB', 'WEAPON_CROWBAR', 'WEAPON_BOTTLE',
    'WEAPON_DAGGER', 'WEAPON_HATCHET', 'WEAPON_KNUCKLE', 'WEAPON_MACHETE',
    'WEAPON_FLASHLIGHT', 'WEAPON_SWITCHBLADE', 'WEAPON_BATTLEAXE',
    'WEAPON_POOLCUE', 'WEAPON_WRENCH', 'WEAPON_STONE_HATCHET',
    'WEAPON_CANDYCANE', 'WEAPON_STUNROD', 'WEAPON_PISTOL', 'WEAPON_PISTOL_MK2',
    'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL', 'WEAPON_PISTOL50',
    'WEAPON_SNSPISTOL', 'WEAPON_SNSPISTOL_MK2', 'WEAPON_HEAVYPISTOL',
    'WEAPON_VINTAGEPISTOL', 'WEAPON_MARKSMANPISTOL', 'WEAPON_REVOLVER',
    'WEAPON_REVOLVER_MK2', 'WEAPON_DOUBLEACTION', 'WEAPON_CERAMICPISTOL',
    'WEAPON_NAVYREVOLVER', 'WEAPON_GADGETPISTOL', 'WEAPON_PISTOLXM3',
    'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_SMG_MK2', 'WEAPON_ASSAULTSMG',
    'WEAPON_COMBATPDW', 'WEAPON_MACHINEPISTOL', 'WEAPON_MINISMG',
    'WEAPON_TECPISTOL', 'WEAPON_PUMPSHOTGUN', 'WEAPON_PUMPSHOTGUN_MK2',
    'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_BULLPUPSHOTGUN',
    'WEAPON_MUSKET', 'WEAPON_HEAVYSHOTGUN', 'WEAPON_DBSHOTGUN',
    'WEAPON_AUTOSHOTGUN', 'WEAPON_COMBATSHOTGUN', 'WEAPON_ASSAULTRIFLE',
    'WEAPON_ASSAULTRIFLE_MK2', 'WEAPON_CARBINERIFLE', 'WEAPON_CARBINERIFLE_MK2',
    'WEAPON_ADVANCEDRIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_SPECIALCARBINE_MK2',
    'WEAPON_BULLPUPRIFLE', 'WEAPON_BULLPUPRIFLE_MK2', 'WEAPON_COMPACTRIFLE',
    'WEAPON_MILITARYRIFLE', 'WEAPON_HEAVYRIFLE', 'WEAPON_TACTICALRIFLE',
    'WEAPON_BATTLERIFLE', 'WEAPON_RAYCARBINE',
    'WEAPON_MG', 'WEAPON_COMBATMG', 'WEAPON_COMBATMG_MK2', 'WEAPON_GUSENBERG',
    'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_HEAVYSNIPER_MK2',
    'WEAPON_MARKSMANRIFLE', 'WEAPON_MARKSMANRIFLE_MK2', 'WEAPON_PRECISIONRIFLE',
    'WEAPON_RPG', 'WEAPON_GRENADELAUNCHER', 'WEAPON_GRENADELAUNCHER_SMOKE',
    'WEAPON_SNOWLAUNCHER',
    'WEAPON_MINIGUN', 'WEAPON_FIREWORK', 'WEAPON_RAILGUN', 'WEAPON_HOMINGLAUNCHER',
    'WEAPON_COMPACTLAUNCHER', 'WEAPON_RAYMINIGUN', 'WEAPON_EMPLAUNCHER',
    'WEAPON_RAILGUNXM3', 'WEAPON_GRENADE', 'WEAPON_BZGAS', 'WEAPON_MOLOTOV',
    'WEAPON_STICKYBOMB', 'WEAPON_PROXMINE', 'WEAPON_SNOWBALL', 'WEAPON_PIPEBOMB',
    'WEAPON_BALL', 'WEAPON_SMOKEGRENADE', 'WEAPON_FLARE', 'WEAPON_PETROLCAN',
    'WEAPON_FIREEXTINGUISHER', 'WEAPON_HAZARDCAN', 'WEAPON_FERTILIZERCAN',
    'WEAPON_ACIDPACKAGE', 'WEAPON_HACKINGDEVICE', 'WEAPON_METALDETECTOR',
    'WEAPON_PARACHUTE', 'WEAPON_STUNGUN',
    'WEAPON_STUNGUN_MP', 'WEAPON_FLAREGUN', 'WEAPON_RAYPISTOL',
}
local function normalize(hash) return hash % 4294967296 end
local namesByHash = {}
for _, name in ipairs(weaponNames) do namesByHash[normalize(GetHashKey(name))] = name end
local unarmed = normalize(GetHashKey('WEAPON_UNARMED'))

function HumalikeWeaponName(hash)
    return namesByHash[normalize(hash)]
end

local function classify(previousWeapon, weapon)
    if previousWeapon == unarmed and weapon ~= unarmed then return 'weapon_drawn' end
    if previousWeapon ~= unarmed and weapon == unarmed then return 'weapon_holstered' end
end

CreateThread(function()
    local previousPed
    local previousWeapon

    while true do
        Wait(250)
        local ped = PlayerPedId()

        if not ped or ped == 0 or not DoesEntityExist(ped) then
            previousPed = nil
            previousWeapon = nil
        else
            local weapon = normalize(GetSelectedPedWeapon(ped))
            if ped ~= previousPed or previousWeapon == nil then
                previousPed = ped
                previousWeapon = weapon
            elseif weapon ~= previousWeapon then
                local eventType = classify(previousWeapon, weapon)
                local previousName, weaponName = namesByHash[previousWeapon], namesByHash[weapon]
                if eventType and previousName and weaponName then
                    TriggerServerEvent('humalike:npc:weaponStateChanged', eventType,
                        previousWeapon, weapon, previousName, weaponName)
                end
                previousWeapon = weapon
            end
        end
    end
end)
