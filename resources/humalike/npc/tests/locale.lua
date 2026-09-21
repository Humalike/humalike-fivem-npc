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
for key in pairs(HumalikeLocale.en) do
    assert(HumalikeLocale.pl[key], 'pl is missing ' .. key)
end
for key in pairs(HumalikeLocale.pl) do
    assert(HumalikeLocale.en[key], 'en is missing ' .. key)
end
print('locale: ok')
