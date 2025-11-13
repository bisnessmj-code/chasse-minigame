--[[
    Configuration du mini-jeu Course-Poursuite 1v1
    Modifiez ces valeurs selon vos besoins
]]

Config = {}

-- ════════════════════════════════════════════════════════════════
-- PARAMÈTRES GÉNÉRAUX
-- ════════════════════════════════════════════════════════════════

Config.Framework = "ESX" -- "ESX", "QB" ou "STANDALONE"
Config.Locale = "fr" -- Langue par défaut
Config.Debug = false -- Mode debug (affiche les logs dans la console)

-- ════════════════════════════════════════════════════════════════
-- NPC ET LOBBY
-- ════════════════════════════════════════════════════════════════

Config.NPC = {
    model = "a_m_y_business_03",
    coords = vector4(-1037.32, -2736.28, 20.17, 240.0),
    interactionDistance = 2.5,
    displayText = "Appuyez sur ~INPUT_CONTEXT~ pour ouvrir le lobby"
}

-- ════════════════════════════════════════════════════════════════
-- VÉHICULES ET POSITIONS DE SPAWN
-- ════════════════════════════════════════════════════════════════

Config.SpawnLocations = {
    {
        name = "Airport Drag Strip",
        teamA = {
            vehicle = vector4(-1172.25, -2993.71, 13.95, 240.0),
            player = vector3(-1172.25, -2993.71, 13.95)
        },
        teamB = {
            vehicle = vector4(-1168.25, -2997.71, 13.95, 240.0),
            player = vector3(-1168.25, -2997.71, 13.95)
        },
        fightZones = { -- Zones de combat possibles
            vector3(-1100.0, -3000.0, 13.95),
            vector3(-1150.0, -2950.0, 13.95),
            vector3(-1050.0, -3050.0, 13.95)
        }
    }
}

Config.VehicleModels = {
    "sultan2",
    "kuruma",
    "elegy",
    "jester",
    "banshee"
}

-- ════════════════════════════════════════════════════════════════
-- RÈGLES DU JEU
-- ════════════════════════════════════════════════════════════════

Config.Game = {
    rounds = 3, -- Nombre de manches
    countdownDuration = 5, -- Durée du compte à rebours (secondes)
    dropTimeLimit = 45, -- Temps max pour drop (secondes)
    zoneJoinTimeLimit = 30, -- Temps max pour rejoindre la zone
    healthPenalty = 5, -- Dégâts par seconde hors zone
    zoneCheckInterval = 1000, -- Intervalle de vérification de zone (ms)
    respawnDelay = 3000, -- Délai avant respawn après mort (ms)
    roundTransitionDelay = 5000 -- Délai entre les manches (ms)
}

-- ════════════════════════════════════════════════════════════════
-- ZONE DE COMBAT
-- ════════════════════════════════════════════════════════════════

Config.Zone = {
    radius = 40.0, -- Rayon de la zone en mètres
    blipSprite = 1,
    blipColor = 1, -- Rouge
    blipScale = 1.5,
    markerType = 1, -- Cylindre
    markerColor = {r = 255, g = 0, b = 0, a = 100},
    beamColor = {r = 255, g = 0, b = 0, a = 150},
    beamHeight = 100.0
}

-- ════════════════════════════════════════════════════════════════
-- ARMES FOURNIES
-- ════════════════════════════════════════════════════════════════

Config.Weapons = {
    {name = "WEAPON_PISTOL", ammo = 150},
    {name = "WEAPON_MICROSMG", ammo = 200}
}

-- ════════════════════════════════════════════════════════════════
-- RÉCOMPENSES
-- ════════════════════════════════════════════════════════════════

Config.Rewards = {
    winner = {
        money = 5000,
        black_money = 2000
    },
    loser = {
        money = 1000
    }
}

-- ════════════════════════════════════════════════════════════════
-- WEBHOOKS DISCORD
-- ════════════════════════════════════════════════════════════════

Config.Webhooks = {
    enabled = true,
    gameStart = "YOUR_WEBHOOK_URL_HERE",
    gameEnd = "YOUR_WEBHOOK_URL_HERE",
    errors = "YOUR_WEBHOOK_URL_HERE",
    colors = {
        INFO = 3447003, -- Bleu
        SUCCESS = 3066993, -- Vert
        WARNING = 15105570, -- Orange
        ERROR = 15158332 -- Rouge
    }
}

-- ════════════════════════════════════════════════════════════════
-- LOCALISATIONS
-- ════════════════════════════════════════════════════════════════

Config.Locales = {
    fr = {
        -- Menu
        menu_title = "Mini-jeu Course-Poursuite",
        menu_subtitle = "Trouvez un adversaire et battez-vous !",
        menu_search = "Rechercher une partie",
        menu_addbot = "Ajouter un bot (Test)",
        menu_close = "Fermer",
        menu_searching = "Recherche en cours...",
        menu_found = "Adversaire trouvé !",
        
        -- Notifications
        notif_searching = "Recherche d'un adversaire...",
        notif_found = "Adversaire trouvé ! Téléportation...",
        notif_countdown = "La partie commence dans %s secondes",
        notif_go = "GO ! Roulez !",
        notif_teamA_drop = "Équipe A : Sortez de votre véhicule !",
        notif_teamB_wait = "Équipe B : Attendez que l'équipe A sorte !",
        notif_teamA_no_drop = "L'équipe A n'a pas drop à temps ! Équipe B gagne !",
        notif_zone_appear = "Une zone de combat est apparue !",
        notif_join_zone = "Rejoignez la zone de combat !",
        notif_in_zone = "Vous êtes dans la zone ! Combat autorisé !",
        notif_left_zone = "Vous avez quitté la zone ! Retournez-y !",
        notif_health_penalty = "Vous perdez de la vie hors de la zone !",
        notif_round_win = "Vous avez gagné la manche %s/%s !",
        notif_round_lose = "Vous avez perdu la manche %s/%s...",
        notif_game_win = "Victoire ! Vous avez gagné %s-%s !",
        notif_game_lose = "Défaite... Score final : %s-%s",
        notif_rewards = "Vous avez reçu $%s",
        
        -- Erreurs
        error_already_in_game = "Vous êtes déjà dans une partie !",
        error_no_players = "Aucun joueur disponible",
        error_instance_full = "L'instance est pleine"
    },
    en = {
        -- Menu
        menu_title = "Chase Mini-Game",
        menu_subtitle = "Find an opponent and fight!",
        menu_search = "Search for a match",
        menu_addbot = "Add a bot (Test)",
        menu_close = "Close",
        menu_searching = "Searching...",
        menu_found = "Opponent found!",
        
        -- Notifications
        notif_searching = "Searching for an opponent...",
        notif_found = "Opponent found! Teleporting...",
        notif_countdown = "Game starts in %s seconds",
        notif_go = "GO! Drive!",
        notif_teamA_drop = "Team A: Exit your vehicle!",
        notif_teamB_wait = "Team B: Wait for Team A to exit!",
        notif_teamA_no_drop = "Team A didn't drop in time! Team B wins!",
        notif_zone_appear = "A fight zone has appeared!",
        notif_join_zone = "Join the fight zone!",
        notif_in_zone = "You're in the zone! Combat allowed!",
        notif_left_zone = "You left the zone! Go back!",
        notif_health_penalty = "You're losing health outside the zone!",
        notif_round_win = "You won round %s/%s!",
        notif_round_lose = "You lost round %s/%s...",
        notif_game_win = "Victory! You won %s-%s!",
        notif_game_lose = "Defeat... Final score: %s-%s",
        notif_rewards = "You received $%s",
        
        -- Errors
        error_already_in_game = "You're already in a game!",
        error_no_players = "No players available",
        error_instance_full = "Instance is full"
    }
}

-- ════════════════════════════════════════════════════════════════
-- FONCTIONS UTILITAIRES
-- ════════════════════════════════════════════════════════════════

function _T(key, ...)
    local locale = Config.Locales[Config.Locale] or Config.Locales["fr"]
    local text = locale[key] or key
    return string.format(text, ...)
end
