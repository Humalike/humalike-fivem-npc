HumalikeNpcReactions = HumalikeNpcReactions or {}

local function persona(ped)
    return HumalikeNpcPopulationClient ~= nil
        and HumalikeNpcPopulationClient.OwnsReactions ~= nil
        and HumalikeNpcPopulationClient.OwnsReactions(ped) == true
end

-- The task form replaces the primary task; withTask only when nothing else runs.
function HumalikeNpcReactions.Own(ped, withTask)
    if not DoesEntityExist(ped) then return end
    SetBlockingOfNonTemporaryEvents(ped, true)
    if withTask then TaskSetBlockingOfNonTemporaryEvents(ped, true) end
end

-- A persona body keeps its reactions blocked; only its mind decides.
function HumalikeNpcReactions.Release(ped, withTask)
    if not DoesEntityExist(ped) then return false end
    if persona(ped) then
        SetBlockingOfNonTemporaryEvents(ped, true)
        return false
    end
    SetBlockingOfNonTemporaryEvents(ped, false)
    if withTask then TaskSetBlockingOfNonTemporaryEvents(ped, false) end
    return true
end
