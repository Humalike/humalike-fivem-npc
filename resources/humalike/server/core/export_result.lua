HumalikeExportResult = HumalikeExportResult or {}

function HumalikeExportResult.Success(value)
    local result = { apiVersion = 1, ok = true }
    if value ~= nil then result.value = value end
    return result
end

function HumalikeExportResult.Failure(code)
    return { apiVersion = 1, ok = false, error = code }
end
