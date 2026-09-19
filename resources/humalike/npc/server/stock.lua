-- The NPC's shelf, set by the server's script: what an NPC has to give, as
-- the server's framework spells its items. HumaLike stores the shelf on the
-- NPC; the NPC reads its exact counts, a deed with `uses_stock` or a
-- catalogue line locks at zero, and each delivered deed takes its share.
-- Every call replaces the whole shelf, so restocking is calling again.
--
-- The export waits for HumaLike's answer: `ok` means the shelf is stored,
-- and `value.stock` is what was stored. Call it from an event handler or a
-- thread (the caller is suspended, never the server).

local ITEM_PATTERN = '^[a-z0-9_.-]+$'
local ITEM_LIMIT = 48
local COUNT_LIMIT = 1000000
local ITEMS_LIMIT = 32

local UUID_PATTERN = ('^%s%%-%s%%-%s%%-%s%%-%s$'):format(
    ('%x'):rep(8), ('%x'):rep(4), ('%x'):rep(4), ('%x'):rep(4), ('%x'):rep(12))

-- Whose shelf this is: a roster NPC, and an external one only once its body
-- is bound (runtime control resolves it the same way). An ambient body has
-- no shelf of its own.
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

-- item -> whole count (integer or integral float, like an order line) or
-- 'unlimited'. An empty table would leave the box as a JSON array, so a
-- shelf names at least one item; a count of 0 is how an item runs out.
local function validatedStock(raw)
    if type(raw) ~= 'table' or next(raw) == nil then return nil, 'invalid_stock' end
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
        -- No credentials yet: the poster answers status 0 without a request.
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
