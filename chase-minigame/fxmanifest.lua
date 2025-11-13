fx_version 'cerulean'
game 'gta5'

author 'Votre Nom'
description 'Mini-jeu Course-Poursuite 1v1 - Un système de combat PvP avec phases de poursuite et de combat au sol - VERSION CORRIGÉE'
version '1.1.0'

lua54 'yes'

-- Scripts
shared_scripts {
    'config.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    'server.lua'
}

-- Interface NUI
ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/script.js'
}

-- Dépendances (optionnelles)
dependencies {
    'es_extended'
    -- 'qb-core' -- Décommenter si vous utilisez QB-Core
}

-- Métadonnées
provide 'chase-minigame'
