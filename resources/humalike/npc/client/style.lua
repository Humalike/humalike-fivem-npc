HumalikeNpcStyle = HumalikeNpcStyle or {}

local COMPONENTS = 12
local PROPS = { 0, 1, 2, 6, 7 }

function HumalikeNpcStyle.Roll(seed)
    local state = (tonumber(seed) or 0) % 2147483648
    return function(count)
        state = (state * 1103515245 + 12345) % 2147483648
        return (state // 65536) % count
    end
end

local function controllable(ped)
    return ped and ped > 0 and DoesEntityExist(ped)
        and not IsPedAPlayer(ped) and NetworkHasControlOfEntity(ped)
end

function HumalikeNpcStyle.ApplyExplicit(ped, style)
    if type(style) ~= 'table' or not controllable(ped) then return false end
    for slot, choice in pairs(style.components or {}) do
        local component, drawable, texture = tonumber(slot), tonumber(choice[1]), tonumber(choice[2]) or 0
        if component and drawable and drawable >= 0
            and drawable < GetNumberOfPedDrawableVariations(ped, component) then
            local textures = GetNumberOfPedTextureVariations(ped, component, drawable)
            SetPedComponentVariation(ped, component, drawable, textures > 0 and texture % textures or 0, 0)
        end
    end
    for slot, choice in pairs(style.props or {}) do
        local prop, drawable, texture = tonumber(slot), tonumber(choice[1]), tonumber(choice[2]) or 0
        if prop and drawable then
            if drawable < 0 then
                ClearPedProp(ped, prop)
            elseif drawable < GetNumberOfPedPropDrawableVariations(ped, prop) then
                local textures = GetNumberOfPedPropTextureVariations(ped, prop, drawable)
                SetPedPropIndex(ped, prop, drawable, textures > 0 and texture % textures or 0, true)
            end
        end
    end
    return true
end

function HumalikeNpcStyle.ApplySeed(ped, seed)
    if not seed or not controllable(ped) then return false end
    local roll = HumalikeNpcStyle.Roll(seed)
    for component = 0, COMPONENTS - 1 do
        local drawables = GetNumberOfPedDrawableVariations(ped, component)
        if drawables > 0 then
            local drawable = roll(drawables)
            local textures = GetNumberOfPedTextureVariations(ped, component, drawable)
            SetPedComponentVariation(ped, component, drawable, textures > 0 and roll(textures) or 0, 0)
        end
    end
    for _, prop in ipairs(PROPS) do
        local drawables = GetNumberOfPedPropDrawableVariations(ped, prop)
        if drawables > 0 then
            local drawable = roll(drawables + 1) - 1
            if drawable < 0 then
                ClearPedProp(ped, prop)
            else
                local textures = GetNumberOfPedPropTextureVariations(ped, prop, drawable)
                SetPedPropIndex(ped, prop, drawable, textures > 0 and roll(textures) or 0, true)
            end
        end
    end
    return true
end

function HumalikeNpcStyle.Dress(ped, entry)
    if type(entry) ~= 'table' then return false end
    local seeded = HumalikeNpcStyle.ApplySeed(ped, entry.style_seed)
    local explicit = HumalikeNpcStyle.ApplyExplicit(ped, entry.style)
    return seeded or explicit
end

AddEventHandler('humalike:npc:ambientPedAssigned', function(_, ped, entry) HumalikeNpcStyle.Dress(ped, entry) end)
AddEventHandler('humalike:npc:persistentPedAssigned', function(_, ped, entry) HumalikeNpcStyle.Dress(ped, entry) end)
