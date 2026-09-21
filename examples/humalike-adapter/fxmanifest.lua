fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'humalike-adapter-example'
description 'Example external provider resource for HumaLike'
version '0.1.0'

dependency 'humalike'

server_script 'server.lua'

client_scripts {
    'client.lua',
    'client_audiohub.lua',
}
