-- The model orders by these names as tag arguments.
local ITEM_PATTERN = '^[a-z][a-z0-9_]*$'
local ITEM_LIMIT = 48
local COUNT_LIMIT = 1000000
local ITEMS_LIMIT = 32

local UUID_PATTERN = ('^%s%%-%s%%-%s%%-%s%%-%s$'):format(
    ('%x'):rep(8), ('%x'):rep(4), ('%x'):rep(4), ('%x'):rep(4), ('%x'):rep(12))

local function resolveNpc(npcId)
    if type(npcId) ~= 'string' or not npcId:match(UUID_PATTERN) then
        return nil, 'invalid_npc'
    end
    local persistent = NpcRegistry and NpcRegistry[npcId] or nil
    if not persistent then return nil, 'npc_not_found' end
    if persistent.type == 'external' and not HumalikeNpcRuntimeControl.Target(npcId) then
        return nil, 'npc_not_bound'
    end
    return persistent
end

local function validatedStock(raw)
    if type(raw) ~= 'table' then return nil, 'invalid_stock' end
    local stock, count = {}, 0
    for item, entry in pairs(raw) do
        if type(item) ~= 'string' or #item > ITEM_LIMIT or not item:match(ITEM_PATTERN) then
            return nil, ('invalid_item:%s'):format(tostring(item))
        end
        if entry ~= 'unlimited' then
            entry = type(entry) == 'number' and math.tointeger(entry) or nil
            if not entry or entry < 0 or entry > COUNT_LIMIT then
                return nil, ('invalid_count:%s'):format(item)
            end
        end
        stock[item] = entry
        count = count + 1
        if count > ITEMS_LIMIT then return nil, 'too_many_items' end
    end
    return stock
end

local function postStock(npcId, stock)
    local settled = promise.new()
    HumalikeHttp.PostAction('set_npc_stock', { npc_id = npcId, stock = stock },
        function(ok, status, body) settled:resolve({ ok = ok, status = status, body = body }) end)
    return Citizen.Await(settled)
end

function HumalikeSetNpcStock(npcId, rawStock)
    local npc, npcError = resolveNpc(npcId)
    if not npc then return HumalikeExportResult.Failure(npcError) end
    local stock, stockError = validatedStock(rawStock)
    if not stock then return HumalikeExportResult.Failure(stockError) end
    local answer = postStock(npcId, stock)
    if not answer.ok then
        -- Status 0 means no credentials yet, nothing was sent.
        if answer.status == 0 then return HumalikeExportResult.Failure('runtime_not_ready') end
        print(('[humalike-npc] set_npc_stock for %s refused (%s)'):format(
            npcId, HumalikeHttp.DescribeFailure(answer.status, answer.body)))
        return HumalikeExportResult.Failure(
            HumaLike.ErrorCode(answer.body) or ('http_%s'):format(tostring(answer.status)))
    end
    local stored = type(answer.body) == 'table' and type(answer.body.stock) == 'table'
        and answer.body.stock or stock
    HumalikeDebug('stock set for npc %s', npcId)
    return HumalikeExportResult.Success({ stock = stored })
end

exports('SetNpcStock', function(npcId, stock)
    return HumalikeSetNpcStock(npcId, stock)
end)
