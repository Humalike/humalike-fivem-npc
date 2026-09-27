AmbientInteractionAdapters = AmbientInteractionAdapters or {}

local entries = {}
local selectedIndexes = {}

local function usable(option, entity)
    if option.canInteract == nil then return true end
    local ok, result = pcall(option.canInteract, entity)
    return ok and result == true
end

AmbientInteractionAdapters.builtin = {
    name = 'builtin',
    priority = -1000,

    Add = function(id, entity, options)
        if type(id) ~= 'string' or not entity or not DoesEntityExist(entity)
            or type(options) ~= 'table' or #options == 0 then return false end
        entries[id] = { entity = entity, options = options }
        return true
    end,

    Remove = function(id)
        entries[id] = nil
        selectedIndexes[id] = nil
    end,
}

local SCAN_MS = 250

local function findClosest()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local closest, closestId, closestDistance, availableOptions = nil, nil, math.huge, nil
    for id, entry in pairs(entries) do
        if not DoesEntityExist(entry.entity) then
            entries[id] = nil
        else
            local distance = #(playerCoords - GetEntityCoords(entry.entity))
            if distance <= ((Config.AmbientControl or {}).InteractionDistance or 3.0)
                and distance < closestDistance then
                local usableOptions = {}
                for _, option in ipairs(entry.options) do
                    if usable(option, entry.entity) then
                        usableOptions[#usableOptions + 1] = option
                    end
                end
                if #usableOptions > 0 then
                    closest, closestId, closestDistance = entry, id, distance
                    availableOptions = usableOptions
                end
            end
        end
    end
    return closest, closestId, availableOptions
end

CreateThread(function()
    local closest, closestId, availableOptions = nil, nil, nil
    local scannedAt = -SCAN_MS
    while true do
        local now = GetGameTimer()
        if now - scannedAt >= SCAN_MS or (closestId and not entries[closestId]) then
            scannedAt = now
            closest, closestId, availableOptions = findClosest()
        end
        if closest then
            local selectedIndex = math.min(selectedIndexes[closestId] or 1, #availableOptions)
            if #availableOptions > 1 then
                if IsControlJustReleased(0, 174) then
                    selectedIndex = selectedIndex > 1 and selectedIndex - 1 or #availableOptions
                elseif IsControlJustReleased(0, 175) then
                    selectedIndex = selectedIndex < #availableOptions and selectedIndex + 1 or 1
                end
            end
            selectedIndexes[closestId] = selectedIndex
            local selectedOption = availableOptions[selectedIndex]
            local choiceHint = #availableOptions > 1 and '~INPUT_CELLPHONE_LEFT~/~INPUT_CELLPHONE_RIGHT~  ' or ''
            BeginTextCommandDisplayHelp('STRING')
            AddTextComponentSubstringPlayerName(
                ('%s~INPUT_CONTEXT~  %s'):format(
                    choiceHint, selectedOption.text or 'interact'))
            EndTextCommandDisplayHelp(0, false, true, -1)
            if IsControlJustReleased(0, 38) and selectedOption.onSelect then
                pcall(selectedOption.onSelect, closest.entity)
            end
            Wait(0)
        else
            Wait(next(entries) and 250 or 1000)
        end
    end
end)
