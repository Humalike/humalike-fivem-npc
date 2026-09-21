fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'humalike-control-test'
description 'Development-only runtime control and entity binding test resource'
version '0.1.0'

dependency 'humalike'

server_script 'server.lua'
client_script 'client.lua'
ui_page 'web/index.html'
files { 'web/index.html', 'web/style.css', 'web/app.js' }
