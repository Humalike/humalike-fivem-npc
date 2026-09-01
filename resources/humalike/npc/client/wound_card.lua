
local held = {}     -- npcId -> { wounds, lines }

local TICK_VISIBLE_MS = 0
local TICK_IDLE_MS = 500
local LINE_HEIGHT = 0.022

local function labels()
    return Config.WoundLabels or {}
end
local function lineFor(wound)
    local label = labels()
    local kind = (label.Kind or {})[wound.kind] or wound.kind
    local region = (label.Region or {})[wound.region] or wound.region
    local severity = (label.Severity or {})[wound.severity] or wound.severity
    return ('%s - %s (%s)'):format(kind, region, severity)
end

RegisterNetEvent('humalike:npc:npcWounds')
AddEventHandler('humalike:npc:npcWounds', function(npcId, wounds)
    if type(npcId) ~= 'string' then return end
    if type(wounds) ~= 'table' or #wounds == 0 then held[npcId] = nil return end
    local lines = {}
    for index, wound in ipairs(wounds) do lines[index] = lineFor(wound) end
    held[npcId] = { wounds = wounds, lines = lines }
end)

local function drawLine(text, x, y, scale, alpha)
    SetTextFont(4)
    SetTextScale(scale, scale)
    SetTextColour(255, 255, 255, alpha)
    SetTextCentre(true)
    SetTextDropShadow()
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end
local function pedFor(npcId)
    local ambient = AmbientPeds and AmbientPeds[npcId] or nil
    if ambient and DoesEntityExist(ambient) then return ambient end
    local static = LoadedPeds and LoadedPeds[npcId] or nil
    if static and DoesEntityExist(static) then return static end
    return nil
end

local function draw(record, coords, distance, state)
    local height = tonumber((Config.Wounds or {}).DisplayHeight) or 0.0
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z + height)
    if not onScreen then return false end
    y = y + (tonumber((Config.Wounds or {}).DisplayScreenOffset) or 0.075)
    local limit = tonumber((Config.Wounds or {}).DisplayDistance) or 3.0
    local alpha = math.floor(255 * math.min(1.0, math.max(0.0, (limit - distance) / (limit * 0.25))))
    if alpha <= 0 then return false end
    local scale = 0.32
    local title = state == 'deceased'
        and (labels().Deceased or 'Deceased')
        or (labels().Title or 'Injuries')
    drawLine(title, x, y - LINE_HEIGHT, scale + 0.03, alpha)
    for index, line in ipairs(record.lines) do
        drawLine(line, x, y + LINE_HEIGHT * (index - 1), scale, alpha)
    end
    return true
end
CreateThread(function()
    Wait(1000)
    TriggerServerEvent('humalike:npc:requestWounds')
end)

CreateThread(function()
    local candidates = {}
    local candidatesAt = -1000000
    while true do
        local wait = TICK_IDLE_MS
        if (Config.Wounds or {}).Display ~= false and next(held) ~= nil then
            local origin = GetEntityCoords(PlayerPedId())
            local limit = tonumber((Config.Wounds or {}).DisplayDistance) or 3.0
            local now = GetGameTimer()
            if now - candidatesAt >= 250 then
                candidates, candidatesAt = {}, now
                local limitSquared = limit * limit
                for npcId, record in pairs(held) do
                    local state = HumalikeDownedState and HumalikeDownedState(npcId) or nil
                    if state == 'wounded' or state == 'deceased' then
                        local ped = pedFor(npcId)
                        if ped then
                            local coords = GetEntityCoords(ped)
                            local dx, dy, dz = origin.x - coords.x, origin.y - coords.y,
                                origin.z - coords.z
                            if dx * dx + dy * dy + dz * dz <= limitSquared then
                                candidates[#candidates + 1] = {
                                    npcId = npcId, record = record, ped = ped,
                                }
                            end
                        end
                    end
                end
            end
            for _, candidate in ipairs(candidates) do
                local ped = candidate.ped
                local state = HumalikeDownedState
                    and HumalikeDownedState(candidate.npcId) or nil
                if DoesEntityExist(ped) and (state == 'wounded' or state == 'deceased') then
                    local coords = GetEntityCoords(ped)
                    local distance = #(origin - coords)
                    if distance <= limit
                        and draw(candidate.record, coords, distance, state) then
                        wait = TICK_VISIBLE_MS
                    end
                end
            end
        end
        Wait(wait)
    end
end)
