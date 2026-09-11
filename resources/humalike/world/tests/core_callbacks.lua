local dataHandler
local responseStatus
local responseSent = 0
local handlerCalls = 0
local activeToken = 'callback-one'

os.time = function() return 100 end
json = {
    decode = function() return { request_id = 'request-1' } end,
    encode = function() return '{}' end,
}
HumaLike = {
    RuntimeCredentials = function()
        return {
            callbackCurrent = {
                token = activeToken,
                valid_from_unix = 0,
                valid_until_unix = 200,
            },
            callbackNext = {
                token = 'callback-next',
                valid_from_unix = 200,
                valid_until_unix = 400,
            },
        }
    end,
}
SetHttpHandler = function(callback)
    local request = {
        path = '/runtime',
        method = 'POST',
        headers = { authorization = 'Bearer callback-one' },
        setDataHandler = function(callbackData) dataHandler = callbackData end,
    }
    local response = {
        writeHead = function(status) responseStatus = status end,
        send = function() responseSent = responseSent + 1 end,
    }
    _G.dispatch = function() callback(request, response) end
end

dofile('../server/core/callbacks.lua')
HumaLike.RegisterCallback('/runtime', function()
    handlerCalls = handlerCalls + 1
    return 200, { ok = true }
end)

dispatch()
assert(type(dataHandler) == 'function', 'authorized callback must begin body collection')
activeToken = 'callback-reassigned'
dataHandler('{}')
assert(responseStatus == 401 and responseSent == 1,
    'callback authorization must be rechecked after asynchronous body collection')
assert(handlerCalls == 0, 'a callback crossing assignment replacement must not execute')

print('core_callbacks: ok')
