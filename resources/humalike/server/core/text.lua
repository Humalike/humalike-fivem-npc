HumaLike = HumaLike or {}

-- `%c` only covers C0 and DEL; C1 controls (C2 80-C2 9F in UTF-8) are refused too.
function HumaLike.CleanText(value, maxLength)
    if type(value) ~= 'string' or value:find('%c') or value:find('\xC2[\x80-\x9F]') then
        return nil
    end
    value = value:match('^%s*(.-)%s*$')
    local length = utf8.len(value)
    if value == '' or not length or length > maxLength then return nil end
    return value
end
