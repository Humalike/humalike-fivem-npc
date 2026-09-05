HumalikeNpcStyle = HumalikeNpcStyle or {}

local COMPONENTS = 12
local PROPS = { 0, 1, 2, 6, 7 }

function HumalikeNpcStyle.Choices(seed, counts)
    local state = (tonumber(seed) or 0) % 2147483648
    local function next()
        state = (state * 1103515245 + 12345) % 2147483648
        return state // 65536
    end
    local choices = {}
    for index, count in ipairs(counts) do
        local drawables = math.max(tonumber(count[1]) or 0, 0)
        local drawable = drawables > 0 and next() % drawables or 0
        local textures = math.max(tonumber(count[2]) or 0, 0)
        local texture = textures > 0 and next() % textures or 0
        choices[index] = { drawable, texture }
    end
    return choices
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
    local counts = {}
    for component = 0, COMPONENTS - 1 do
        counts[#counts + 1] = { GetNumberOfPedDrawableVariations(ped, component), 0 }
    end
    local choices = HumalikeNpcStyle.Choices(seed, counts)
    for component = 0, COMPONENTS - 1 do
        local drawables = GetNumberOfPedDrawableVariations(ped, component)
        if drawables > 1 then
            local choice = choices[component + 1]
            local drawable = choice[1] % drawables
            local textures = GetNumberOfPedTextureVariations(ped, component, drawable)
            SetPedComponentVariation(ped, component, drawable, textures > 0 and (choice[2] + choice[1]) % textures or 0, 0)
        end
    end
    local propCounts = {}
    for _, prop in ipairs(PROPS) do
        propCounts[#propCounts + 1] = { GetNumberOfPedPropDrawableVariations(ped, prop) + 1, 0 }
    end
    local propChoices = HumalikeNpcStyle.Choices(seed + 7919, propCounts)
    for index, prop in ipairs(PROPS) do
        local drawables = GetNumberOfPedPropDrawableVariations(ped, prop)
        if drawables > 0 then
            local drawable = propChoices[index][1] % (drawables + 1) - 1
            if drawable < 0 then
                ClearPedProp(ped, prop)
            else
                local textures = GetNumberOfPedPropTextureVariations(ped, prop, drawable)
                SetPedPropIndex(ped, prop, drawable, textures > 0 and propChoices[index][2] % textures or 0, true)
            end
        end
    end
    return true
end

function HumalikeNpcStyle.Dress(ped, entry)
    if type(entry) ~= 'table' then return false end
    if type(entry.style) == 'table' then return HumalikeNpcStyle.ApplyExplicit(ped, entry.style) end
    return HumalikeNpcStyle.ApplySeed(ped, entry.style_seed)
end

AddEventHandler('humalike:npc:ambientPedAssigned', function(_, ped, entry) HumalikeNpcStyle.Dress(ped, entry) end)
AddEventHandler('humalike:npc:persistentPedAssigned', function(_, ped, entry) HumalikeNpcStyle.Dress(ped, entry) end)
