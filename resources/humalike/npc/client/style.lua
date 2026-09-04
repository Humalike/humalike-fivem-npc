--- A persona's fixed look on whatever ped it is leased onto.
--
-- GTA streets about 150 ped models, so personas share models. Every model
-- ships several outfits and heads the game rolls at random at spawn; the
-- control plane gives each persona a `style_seed`, and this maps it onto the
-- model's own variation counts so the persona wears the same combination on
-- every ped it inhabits, and two personas on one model look like two people.
-- Counts are read live from the ped, so addon models need no catalogue.

local COMPONENTS = 12 -- 0 face .. 11 armour/decal
local PROPS = { 0, 1, 2, 6, 7 } -- hat, glasses, ears, watch, bracelet

--- Deterministic per-slot choices from one seed: bits are peeled off a simple
--- LCG so slots do not correlate; `counts` is a list of {drawables, textures}.
function HumalikeStyleFor(seed, counts)
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

--- Dress `ped` in an explicit look: { components = { ["3"] = { drawable, texture } },
--- props = { ["0"] = { drawable, texture } } } with drawable -1 = no prop.
--- Slots the look does not mention keep what the game rolled.
function HumalikeApplyExplicitStyle(ped, style)
    if type(style) ~= 'table' or not ped or ped <= 0 or not DoesEntityExist(ped) then return false end
    if IsPedAPlayer(ped) or not NetworkHasControlOfEntity(ped) then return false end
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

--- Dress `ped` as `seed` says. No-op without a seed, for a ped we cannot
--- control, or for player models (their wardrobe is the player's own).
function HumalikeApplyPedStyle(ped, seed)
    if not seed or not ped or ped <= 0 or not DoesEntityExist(ped) then return false end
    if IsPedAPlayer(ped) or not NetworkHasControlOfEntity(ped) then return false end
    local counts = {}
    for component = 0, COMPONENTS - 1 do
        local drawables = GetNumberOfPedDrawableVariations(ped, component)
        -- Texture count depends on the drawable, so pass the max over drawables
        -- and clamp after the pick.
        counts[#counts + 1] = { drawables, 0 }
    end
    local choices = HumalikeStyleFor(seed, counts)
    for component = 0, COMPONENTS - 1 do
        local choice = choices[component + 1]
        local drawables = GetNumberOfPedDrawableVariations(ped, component)
        if drawables > 1 then
            local drawable = choice[1] % drawables
            local textures = GetNumberOfPedTextureVariations(ped, component, drawable)
            local texture = textures > 0 and (choice[2] + choice[1]) % textures or 0
            SetPedComponentVariation(ped, component, drawable, texture, 0)
        end
    end
    local propCounts = {}
    for _, prop in ipairs(PROPS) do
        propCounts[#propCounts + 1] = { GetNumberOfPedPropDrawableVariations(ped, prop) + 1, 0 }
    end
    local propChoices = HumalikeStyleFor(seed + 7919, propCounts)
    for index, prop in ipairs(PROPS) do
        local drawables = GetNumberOfPedPropDrawableVariations(ped, prop)
        if drawables > 0 then
            local drawable = propChoices[index][1] % (drawables + 1) - 1 -- -1 = none
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

local function dress(ped, entry)
    if type(entry) ~= 'table' then return end
    -- The chosen look wins; the seed only covers slots the look leaves out.
    if type(entry.style) == 'table' then
        HumalikeApplyExplicitStyle(ped, entry.style)
    else
        HumalikeApplyPedStyle(ped, entry.style_seed)
    end
end

AddEventHandler('humalike:npc:ambientPedAssigned', function(_, ped, entry) dress(ped, entry) end)
AddEventHandler('humalike:npc:persistentPedAssigned', function(_, ped, entry) dress(ped, entry) end)
