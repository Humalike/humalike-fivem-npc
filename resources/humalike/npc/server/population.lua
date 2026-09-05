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

local function listDirectory(resource, directory)
    local root = GetResourcePath(resource)
    if type(root) ~= 'string' or type(io) ~= 'table' or not io.popen then return {} end
    local full = root .. '/' .. directory
    local command = package.config:sub(1, 1) == '\\'
        and ('dir /b "%s" 2>nul'):format((full:gsub('/', '\\')))
        or ('ls -1 "%s" 2>/dev/null'):format(full)
    local ok, pipe = pcall(io.popen, command)
    if not ok or not pipe then return {} end
    local names = {}
    for line in pipe:lines() do names[#names + 1] = line end
    pipe:close()
    return names
end

local function expand(resource, path)
    if not path:find('*', 1, true) then return { path } end
    local directory, name = path:match('^(.-)/?([^/]*)$')
    if directory:find('*', 1, true) or not path:match('^[%w%._%-/ ]+$') then return {} end
    local pattern = '^' .. name:gsub('[%^%$%(%)%%%.%[%]%+%-%?]', '%%%0'):gsub('%*', '.*') .. '$'
    local paths = {}
    for _, entry in ipairs(listDirectory(resource, directory)) do
        if entry:match(pattern) then
            paths[#paths + 1] = directory ~= '' and directory .. '/' .. entry or entry
        end
    end
    return paths
end

local function readFile(resource, path)
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
                for _, path in ipairs(expand(resource, candidate.path)) do
                    local key = resource .. '/' .. path
                    if not seen[key] then
                        seen[key] = true
                        local content = readFile(resource, path)
                        if content and #content <= MAX_FILE_BYTES
                            and total + #content <= MAX_TOTAL_BYTES then
                            total = total + #content
                            files[#files + 1] = {
                                kind = candidate.kind,
                                resource = resource,
                                path = path,
                                content = content,
                            }
                        end
                    end
                end
            end
        end
    end
    return files
end

function HumalikeNpcPopulation.Upload(onDone)
    local files = HumalikeNpcPopulation.Collect()
    HumalikeHttp.PostAction('upload_population_files', { files = files }, function(ok, status, body)
        if ok then
            HumalikeDebug('population files: %d sent, edge forwarded %s, dropped %s', #files,
                type(body) == 'table' and tostring(body.forwarded) or '?',
                type(body) == 'table' and tostring(body.dropped) or '?')
        else
            print(('[humalike-npc] upload_population_files failed (HTTP %s)'):format(tostring(status)))
        end
        if onDone then onDone(ok == true) end
    end)
end
