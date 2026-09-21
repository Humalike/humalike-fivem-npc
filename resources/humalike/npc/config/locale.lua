-- Texts the resource itself shows to players, in the language
-- `humalike_ui_language` selects. Convar-backed labels (revive, mortuary,
-- wounds) stay overridable one by one.
HumalikeLocale = {
    en = { help_up = 'Help up' },
    pl = { help_up = 'Pomóż wstać' },
}

function HumalikeUiLanguage()
    local language = tostring(Config.UiLanguage or 'en'):lower():match('^([a-z]+)') or 'en'
    return HumalikeLocale[language] and language or 'en'
end

function HumalikeText(key)
    local texts = HumalikeLocale[HumalikeUiLanguage()]
    return texts[key] or HumalikeLocale.en[key] or key
end
