-- Population files: declared data_file entries and streamed overrides are
-- collected from every started resource and sent once.
local resources = {
    { name = 'humalike', state = 'started', meta = {}, files = {} },
    {
        name = 'custom_peds',
        state = 'started',
        meta = {
            { 'PED_METADATA_FILE', '"peds.meta"' },
            { 'VEHICLE_METADATA_FILE', '"vehicles.meta"' },
            { 'PED_METADATA_FILE', '"metas/*_peds.meta"' },
        },
        files = { ['peds.meta'] = '<CPedModelInfo__InitDataList/>' },
    },
    {
        name = 'population_tweaks',
        state = 'started',
        meta = { { 'DLC_POP_GROUPS', '["popgroups.ymt"]' }, { 'POPSCHED_FILE', '["data/popcycle.dat"]' } },
        files = {
            ['popgroups.ymt'] = '<CPopGroupList/>',
            ['data/popcycle.dat'] = 'POP_SCHEDULE:',
            ['stream/zonebind.ymt'] = '<CPopZoneData/>',
        },
    },
    {
        name = 'stopped_peds',
        state = 'stopped',
        meta = { { 'PED_METADATA_FILE', '"peds.meta"' } },
        files = { ['peds.meta'] = 'never read' },
    },
}

function GetNumResources() return #resources end
function GetResourceByFindIndex(index) return resources[index + 1].name end
local function byName(name)
    for _, resource in ipairs(resources) do
        if resource.name == name then return resource end
    end
end
function GetResourceState(name) return byName(name).state end
function GetNumResourceMetadata(name, key)
    assert(key == 'data_file')
    return #byName(name).meta
end
function GetResourceMetadata(name, key, index)
    local entry = byName(name).meta[index + 1]
    if not entry then return nil end
    if key == 'data_file' then return entry[1] end
    if key == 'data_file_extra' then return entry[2] end
end
function LoadResourceFile(name, path) return byName(name).files[path] end
json = {
    decode = function(text)
        if text:sub(1, 1) == '[' then return { text:match('%["([^"]+)"%]') } end
        if text:sub(1, 1) == '"' then return text:match('"([^"]+)"') end
        error('not json')
    end,
}
local posted
HumalikeHttp = {
    PostAction = function(action, payload, callback)
        posted = { action = action, payload = payload }
        callback(true, 200, { forwarded = 4, dropped = 0 })
    end,
}
local debugLines = {}
function HumalikeDebug(fmt, ...) debugLines[#debugLines + 1] = fmt:format(...) end

dofile('server/population.lua')

local files = HumalikeCollectPopulationFiles()
local got = {}
for _, file in ipairs(files) do
    got[#got + 1] = ('%s %s %s'):format(file.kind, file.resource, file.path)
end
table.sort(got)
local expected = {
    'peds_meta custom_peds peds.meta',
    'popcycle population_tweaks data/popcycle.dat',
    'popgroups population_tweaks popgroups.ymt',
    'zonebind population_tweaks stream/zonebind.ymt',
}
assert(#got == #expected, 'collected ' .. table.concat(got, ', '))
for index, line in ipairs(expected) do
    assert(got[index] == line, ('expected %s, got %s'):format(line, got[index]))
end
for _, file in ipairs(files) do
    assert(type(file.content) == 'string' and #file.content > 0, file.path .. ' has content')
end

HumalikeUploadPopulationFiles()
assert(posted.action == 'upload_population_files')
assert(#posted.payload.files == 4)
assert(debugLines[1] == 'population files: 4 sent, edge forwarded 4, dropped 0', debugLines[1])
print('server_population ok')
