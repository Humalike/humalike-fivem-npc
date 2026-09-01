HumalikeWorldServerContracts = {}

local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

function HumalikeWorldServerContracts.Copy(value) return copy(value) end

function HumalikeWorldServerContracts.Identity(value)
    if type(value) ~= 'table' or value.characterId == nil then return nil, 'characterId required' end
    local characterId = tostring(value.characterId)
    if characterId == '' or #characterId > 128 then return nil, 'invalid characterId' end
    local name = tostring(value.name or characterId)
    if #name > 128 then return nil, 'invalid name' end
    return { characterId = characterId, name = name, metadata = copy(value.metadata) }
end
