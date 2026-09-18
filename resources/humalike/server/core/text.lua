HumaLike = HumaLike or {}

-- One free-text value the resource forwards: trimmed, printable, non-empty,
-- valid UTF-8 and at most `maxLength` characters. Nil otherwise.
--
-- `%c` is byte-wise ASCII (C0 and DEL); the C1 controls (U+0080-U+009F, the
-- two-byte sequences C2 80-C2 9F in UTF-8) are what the backend also refuses,
-- so a NEL in a value fails here instead of as a 422 at the edge.
function HumaLike.CleanText(value, maxLength)
    if type(value) ~= 'string' or value:find('%c') or value:find('\xC2[\x80-\x9F]') then
        return nil
    end
    value = value:match('^%s*(.-)%s*$')
    local length = utf8.len(value)
    if value == '' or not length or length > maxLength then return nil end
    return value
end
