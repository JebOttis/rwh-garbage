fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'RWH'
description 'RWH Garbage Job Script (qbx_core + ox_inventory/ox_target/ox_lib)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua', -- included in case you want persistence later
    'server/main.lua',
}

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'qbx_core', -- or qb-core; configurable in Config.Framework
}
