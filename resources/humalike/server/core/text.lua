HumaLike = HumaLike or {}

-- One free-text value the resource forwards: trimmed, printable, non-empty,
-- valid UTF-8 and at most `maxLength` characters. Nil otherwise.
function HumaLike.CleanText(value, maxLength)
    if type(value) ~= 'string' or value:find('%c') then return nil end
    value = value:match('^%s*(.-)%s*$')
    local length = utf8.len(value)
    if value == '' or not length or length > maxLength then return nil end
    return value
end
