HumalikeNpcPopulation = HumalikeNpcPopulation or {}

local KINDS = {
    DLC_POP_GROUPS = 'popgroups',
    POPSCHED_FILE = 'popcycle',
    ZONEBIND_FILE = 'zonebind',
    PED_METADATA_FILE = 'peds_meta',
}
local STREAMED = {
    { kind = 'popgroups', path = 'stream/popgroups.ymt' },
    { kind = 'popcycle', path = 'stream/popcycle.dat' },
    { kind = 'zonebind', path = 'stream/zonebind.ymt' },
}
local MAX_FILE_BYTES = 4 * 1024 * 1024
local MAX_TOTAL_BYTES = 12 * 1024 * 1024

local function declaredFiles(resource)
    local found = {}
    for index = 0, (GetNumResourceMetadata(resource, 'data_file') or 0) - 1 do
        local kind = KINDS[GetResourceMetadata(resource, 'data_file', index) or '']
        if kind then
            local extra = GetResourceMetadata(resource, 'data_file_extra', index)
            local ok, decoded = pcall(json.decode, extra or '')
            local path = ok and decoded or extra
            if type(path) == 'table' then path = path[1] end
            if type(path) == 'string' and path ~= '' then
                found[#found + 1] = { kind = kind, path = path }
            end
        end
    end
    return found
end

local function readFile(resource, path)
    if path:find('*', 1, true) then return nil end
    local content = LoadResourceFile(resource, path)
    if type(content) ~= 'string' or content == '' then return nil end
    return content
end

function HumalikeNpcPopulation.Collect()
    local files, total, seen = {}, 0, {}
    for index = 0, (GetNumResources() or 0) - 1 do
        local resource = GetResourceByFindIndex(index)
        if resource and GetResourceState(resource) == 'started' then
            local candidates = declaredFiles(resource)
            for _, probe in ipairs(STREAMED) do candidates[#candidates + 1] = probe end
            for _, candidate in ipairs(candidates) do
                local key = resource .. '/' .. candidate.path
                if not seen[key] then
                    seen[key] = true
                    local content = readFile(resource, candidate.path)
                    if content and #content <= MAX_FILE_BYTES
                        and total + #content <= MAX_TOTAL_BYTES then
                        total = total + #content
                        files[#files + 1] = {
                            kind = candidate.kind,
                            resource = resource,
                            path = candidate.path,
                            content = content,
                        }
                    end
                end
            end
        end
    end
    return files
end

function HumalikeNpcPopulation.Upload()
    local files = HumalikeNpcPopulation.Collect()
    HumalikeHttp.PostAction('upload_population_files', { files = files }, function(ok, status, body)
        if not ok then
            print(('[humalike-npc] upload_population_files failed (HTTP %s)'):format(tostring(status)))
            return
        end
        HumalikeDebug('population files: %d sent, edge forwarded %s, dropped %s', #files,
            type(body) == 'table' and tostring(body.forwarded) or '?',
            type(body) == 'table' and tostring(body.dropped) or '?')
    end)
end
