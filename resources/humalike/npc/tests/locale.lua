Config = {}
dofile('config/locale.lua')
assert(HumalikeUiLanguage() == 'en')
assert(HumalikeText('help_up') == 'Help up')
Config.UiLanguage = 'pl'
assert(HumalikeText('help_up') == 'Pomóż wstać')
Config.UiLanguage = 'PL-pl'
assert(HumalikeUiLanguage() == 'pl', 'a region suffix is ignored')
Config.UiLanguage = 'xx'
assert(HumalikeUiLanguage() == 'en', 'an unknown language falls back to English')
assert(HumalikeText('missing') == 'missing')
Config.UiLanguage = 'es'
assert(HumalikeText('help_up') == 'Ayudar a levantarse')
Config.UiLanguage = 'fr-FR'
assert(HumalikeText('help_up') == 'Aider à se relever')
for language, texts in pairs(HumalikeLocale) do
    for key in pairs(HumalikeLocale.en) do
        assert(texts[key], language .. ' is missing ' .. key)
    end
    for key in pairs(texts) do
        assert(HumalikeLocale.en[key], 'en is missing ' .. key .. ' (' .. language .. ')')
    end
end
print('locale: ok')
