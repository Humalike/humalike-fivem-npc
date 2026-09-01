HumalikeWorldRegistry = { entries = {}, revision = 0 }

local function touch()
    HumalikeWorldRegistry.revision = HumalikeWorldRegistry.revision + 1
end

local function same(a, b)
    for _, key in ipairs({ 'npcId', 'entity', 'entityId', 'networkId', 'modelHash',
        'runtimeToken', 'kind', 'activity', 'ownerResource' }) do
        if a[key] ~= b[key] then return false end
    end
    return true
end

function HumalikeWorldRegistry.Register(value)
    local entry, reason = HumalikeWorldContracts.NpcRegistration(value)
    if not entry then return false, reason end
    local previous = HumalikeWorldRegistry.entries[entry.npcId]
    if previous and same(previous, entry) then return true end
    entry.generation = previous and previous.generation + 1 or 1
    HumalikeWorldRegistry.entries[entry.npcId] = entry
    touch()
    return true
end

function HumalikeWorldRegistry.Update(npcId, patch, ownerResource)
    local entry = HumalikeWorldRegistry.entries[npcId]
    if not entry or type(patch) ~= 'table' then return false end
    if ownerResource and entry.ownerResource ~= ownerResource then return false, 'not owner' end
    local candidate = HumalikeWorldContracts.Copy(entry)
    for _, key in ipairs({ 'entity', 'entityId', 'networkId', 'modelHash',
        'runtimeToken', 'kind', 'activity' }) do
        if patch[key] ~= nil then candidate[key] = patch[key] end
    end
    candidate.ownerResource = entry.ownerResource
    local validated, reason = HumalikeWorldContracts.NpcRegistration(candidate)
    if not validated then return false, reason end
    if same(entry, validated) then return true end
    validated.generation = entry.generation + 1
    HumalikeWorldRegistry.entries[npcId] = validated
    touch()
    return true
end

function HumalikeWorldRegistry.Unregister(npcId, ownerResource)
    if type(npcId) ~= 'string' or not HumalikeWorldRegistry.entries[npcId] then return false end
    if ownerResource and HumalikeWorldRegistry.entries[npcId].ownerResource ~= ownerResource then
        return false, 'not owner'
    end
    HumalikeWorldRegistry.entries[npcId] = nil
    touch()
    return true
end

function HumalikeWorldRegistry.SetActivity(npcId, activity, ownerResource)
    local entry = HumalikeWorldRegistry.entries[npcId]
    if not entry or (activity ~= 'idle' and activity ~= 'nearby'
        and activity ~= 'moving' and activity ~= 'talking') then return false end
    if ownerResource and entry.ownerResource ~= ownerResource then return false, 'not owner' end
    if entry.activity ~= activity then
        entry.activity = activity
        touch()
    end
    return true
end

function HumalikeWorldRegistry.RemoveOwner(resource)
    local removed = 0
    for npcId, entry in pairs(HumalikeWorldRegistry.entries) do
        if entry.ownerResource == resource then
            HumalikeWorldRegistry.entries[npcId] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then touch() end
    return removed
end

function HumalikeWorldRegistry.Count()
    local count = 0
    for _ in pairs(HumalikeWorldRegistry.entries) do count = count + 1 end
    return count
end
