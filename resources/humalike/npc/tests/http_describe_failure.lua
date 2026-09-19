-- DescribeFailure reads external response data: anything not shaped as a
-- list of {field, message} tables is ignored, never an error.
HumalikeHttp = HumalikeHttp or {}
dofile('server/http.lua')

local describe = HumalikeHttp.DescribeFailure
assert(describe(400, { error = { code = 'VALIDATION_ERROR', details = {
    { field = 'actions.0.key', message = 'bad key' }, 'garbage', { message = 'no field' } } } })
    == 'HTTP 400 VALIDATION_ERROR: actions.0.key: bad key; nil: no field')
assert(describe(400, { error = { code = 'X', details = 'not a list' } }) == 'HTTP 400 X')
assert(describe(500, nil) == 'HTTP 500')
assert(describe(422, { error = 'string' }) == 'HTTP 422')
print('http_describe_failure ok')
