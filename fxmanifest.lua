fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Dei'
description 'Sistema de drift con NUI overlay - Dei Ecosystem'
-- Requiere: es_extended o qb-core, oxmysql o mysql-async (si aplica)
version '1.0'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/assets/css/themes.css',
    'html/assets/css/styles.css',
    'html/assets/js/app.js',
    'html/assets/fonts/Gilroy-Light.otf',
    'html/assets/fonts/Gilroy-ExtraBold.otf'
}

shared_scripts {
    "config.lua",
    "shared/utils.lua"
}

client_scripts {
    "client/framework.lua",
    "client/main.lua"
}

server_scripts {
    "server/framework.lua",
    "server/main.lua"
}

server_exports {
    'GetDriftLeaderboard'
}
