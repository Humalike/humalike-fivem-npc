--- Population files: what this server streets, sent once per boot.
--
-- A dynamic NPC is leased onto a street pedestrian of exactly its ped model,
-- so the control plane picks each persona's model from the models the game
-- spawns on THIS server. The game decides that from four data files; a server
-- that ships its own copies (or addon peds) declares them in a resource
-- manifest as `data_file` entries, which the manifest metadata exposes here.
-- Stock GTA files need no upload — the control plane holds those.
--
-- Wire: POST upload_population_files { files = [{ kind, resource, path,
-- content }] }. Content is sent verbatim (text); the control plane
-- de-duplicates by content hash, so re-sending every boot is cheap.

local KINDS = {
    DLC_POP_GROUPS = 'popgroups',
    POPSCHED_FILE = 'popcycle',
    ZONEBIND_FILE = 'zonebind',
    PED_METADATA_FILE = 'peds_meta',
}

--- Overrides some servers stream instead of declaring; probed by name.
local STREAMED_CANDIDATES = {
    { kind = 'popgroups', path = 'stream/popgroups.ymt' },
    { kind = 'popcycle', path = 'stream/popcycle.dat' },
    { kind = 'zonebind', path = 'stream/zonebind.ymt' },
}

local MAX_FILE_BYTES = 4 * 1024 * 1024
local MAX_TOTAL_BYTES = 12 * 1024 * 1024

local function declaredFiles(resource)
    local found = {}
    local count = GetNumResourceMetadata(resource, 'data_file') or 0
    for index = 0, count - 1 do
        local kind = KINDS[GetResourceMetadata(resource, 'data_file', index) or '']
        if kind then
            -- The manifest stores the path JSON-encoded: "peds.meta" (or a list).
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
    if path:find('*', 1, true) then return nil end -- globs are not resolvable here
    local content = LoadResourceFile(resource, path)
    if type(content) ~= 'string' or content == '' then return nil end
    return content
end

--- Every population data file every started resource declares or streams.
function HumalikeCollectPopulationFiles()
    local files, total, seen = {}, 0, {}
    for index = 0, (GetNumResources() or 0) - 1 do
        local resource = GetResourceByFindIndex(index)
        if resource and GetResourceState(resource) == 'started' then
            local candidates = declaredFiles(resource)
            for _, probe in ipairs(STREAMED_CANDIDATES) do
                candidates[#candidates + 1] = probe
            end
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

function HumalikeUploadPopulationFiles()
    local files = HumalikeCollectPopulationFiles()
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
