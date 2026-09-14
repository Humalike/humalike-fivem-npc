HumaLike = HumaLike or {}

local delays = { 250, 500, 1000, 2000 }

local function jitter(base, randomUnit)
    local sample = randomUnit
    if type(sample) ~= 'number' then sample = math.random() end
    return math.floor(base * (0.8 + sample * 0.4))
end

function HumaLike.RetryDelay(attempt, randomUnit)
    return jitter(delays[math.min(math.max(attempt or 1, 1), #delays)], randomUnit)
end

function HumaLike.RenewalDelay(randomUnit)
    return jitter(10000, randomUnit)
end
