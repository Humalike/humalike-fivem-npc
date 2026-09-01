HumalikeDispatch = {}

function HumalikeDispatch.Available()
    return HumalikeSelectedProvider('dispatch') ~= nil
end

function HumalikeDispatch.Report(kind, payload)
    local ok, value = HumalikeProviderCall('dispatch', 'Report', kind, payload)
    return ok and value ~= false
end
