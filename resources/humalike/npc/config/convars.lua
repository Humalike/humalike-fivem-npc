-- Shared config reads convars through these helpers so the server can send its
-- values to every client. A setting written with `set` (server-only) then
-- applies on the client exactly as `setr` would. Every registered name is
-- client-visible by definition; credentials are read with GetConvar directly
-- in server-only files and never registered here.
HumalikeConvars = HumalikeConvars or { order = {}, known = {}, overrides = {}, builders = {} }

local UNSET = '\1humalike:unset'
local MAX_VALUE_LENGTH = 512

local function remember(name)
    if HumalikeConvars.known[name] then return end
    HumalikeConvars.known[name] = true
    HumalikeConvars.order[#HumalikeConvars.order + 1] = name
end

function HumalikeConvar(name, default)
    remember(name)
    local override = HumalikeConvars.overrides[name]
    if override ~= nil then return override end
    return GetConvar(name, default)
end

function HumalikeConvarInt(name, default)
    remember(name)
    local override = HumalikeConvars.overrides[name]
    if override == nil then return GetConvarInt(name, default) end
    local number = tonumber(override)
    return number and math.tointeger(math.floor(number)) or default
end

-- Config built from convars is declared through a builder so the client can
-- rebuild it once the server's values arrive.
function HumalikeDefineConfig(build)
    HumalikeConvars.builders[#HumalikeConvars.builders + 1] = build
    build()
end

function HumalikeConvarSnapshot()
    local snapshot = {}
    for _, name in ipairs(HumalikeConvars.order) do
        local value = GetConvar(name, UNSET)
        if value ~= UNSET then snapshot[name] = value end
    end
    return snapshot
end

function HumalikeApplyConvarSnapshot(snapshot)
    if type(snapshot) ~= 'table' then return false end
    local overrides = {}
    for name, value in pairs(snapshot) do
        if type(name) ~= 'string' then return false end
        if type(value) == 'number' then value = tostring(value) end
        if type(value) ~= 'string' or #value > MAX_VALUE_LENGTH or value:find('%c') then
            return false
        end
        if HumalikeConvars.known[name] then overrides[name] = value end
    end
    HumalikeConvars.overrides = overrides
    for _, build in ipairs(HumalikeConvars.builders) do build() end
    return true
end
