--[[
    Script Serveur - Mini-jeu Course-Poursuite 1v1
    Gestion du matchmaking, instances et logique de jeu
    VERSION CORRIGÉE avec debug
]]

-- ════════════════════════════════════════════════════════════════
-- VARIABLES GLOBALES
-- ════════════════════════════════════════════════════════════════

local ESX = nil
local QBCore = nil

-- Initialisation du framework
if Config.Framework == "ESX" then
    ESX = exports["es_extended"]:getSharedObject()
elseif Config.Framework == "QB" then
    QBCore = exports['qb-core']:GetCoreObject()
end

-- Gestion des files d'attente et instances
local matchmakingQueue = {}
local activeInstances = {}
local nextInstanceId = 1
local playerInstances = {} -- Associe chaque joueur à son instance

-- ════════════════════════════════════════════════════════════════
-- FONCTION DE DEBUG
-- ════════════════════════════════════════════════════════════════

local function debugLog(message)
    if Config.Debug then
        print("^2[CHASE-SERVER DEBUG]^7 " .. message)
    end
end

-- ════════════════════════════════════════════════════════════════
-- CLASSES ET STRUCTURES
-- ════════════════════════════════════════════════════════════════

local GameInstance = {}
GameInstance.__index = GameInstance

function GameInstance:new(id, playerA, playerB)
    local instance = setmetatable({}, GameInstance)
    
    instance.id = id
    instance.players = {
        teamA = {source = playerA, score = 0, dropped = false, dropCoords = nil},
        teamB = {source = playerB, score = 0, dropped = false, dropCoords = nil}
    }
    instance.currentRound = 1
    instance.phase = "WAITING" -- WAITING, COUNTDOWN, DRIVING, COMBAT, FINISHED
    instance.location = Config.SpawnLocations[1] -- Peut être randomisé
    instance.fightZone = nil
    instance.vehicles = {}
    instance.startTime = os.time()
    instance.dropTimer = nil
    instance.roundTimer = nil
    
    debugLog("Instance créée: ID " .. id .. " | Joueur A: " .. playerA .. " | Joueur B: " .. playerB)
    
    return instance
end

function GameInstance:swapTeams()
    debugLog("Instance " .. self.id .. ": Échange des équipes")
    
    local temp = self.players.teamA
    self.players.teamA = self.players.teamB
    self.players.teamB = temp
    
    -- Réinitialiser les états de drop
    self.players.teamA.dropped = false
    self.players.teamB.dropped = false
    self.players.teamA.dropCoords = nil
    self.players.teamB.dropCoords = nil
    
    debugLog("Nouvelles équipes - TeamA: " .. self.players.teamA.source .. " | TeamB: " .. self.players.teamB.source)
end

function GameInstance:cleanup()
    debugLog("Instance " .. self.id .. ": Début du nettoyage")
    
    -- Supprimer les véhicules
    for _, vehicle in pairs(self.vehicles) do
        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
            debugLog("Véhicule supprimé: " .. vehicle)
        end
    end
    
    -- Annuler les timers
    if self.dropTimer then
        ClearTimeout(self.dropTimer)
        debugLog("Timer de drop annulé")
    end
    if self.roundTimer then
        ClearTimeout(self.roundTimer)
        debugLog("Timer de round annulé")
    end
    
    -- Retirer les joueurs de l'instance
    playerInstances[self.players.teamA.source] = nil
    playerInstances[self.players.teamB.source] = nil
    
    debugLog("Instance " .. self.id .. ": Nettoyage terminé")
end

-- ════════════════════════════════════════════════════════════════
-- FONCTIONS UTILITAIRES
-- ════════════════════════════════════════════════════════════════

local function sendLog(webhookType, title, description, color)
    if not Config.Webhooks.enabled then return end
    
    local webhook = Config.Webhooks[webhookType]
    if not webhook or webhook == "YOUR_WEBHOOK_URL_HERE" then return end
    
    local embed = {
        {
            ["title"] = title,
            ["description"] = description,
            ["color"] = color or Config.Webhooks.colors.INFO,
            ["footer"] = {
                ["text"] = "Chase Mini-Game • " .. os.date("%Y-%m-%d %H:%M:%S")
            }
        }
    }
    
    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST', 
        json.encode({embeds = embed}), {['Content-Type'] = 'application/json'})
end

local function getPlayerName(source)
    if Config.Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(source)
        return xPlayer and xPlayer.getName() or "Inconnu"
    elseif Config.Framework == "QB" then
        local Player = QBCore.Functions.GetPlayer(source)
        return Player and Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname or "Inconnu"
    else
        return GetPlayerName(source) or "Inconnu"
    end
end

local function notifyPlayer(source, message, type)
    type = type or "info"
    
    if Config.Framework == "ESX" then
        TriggerClientEvent('esx:showNotification', source, message)
    elseif Config.Framework == "QB" then
        TriggerClientEvent('QBCore:Notify', source, message, type)
    else
        TriggerClientEvent('chat:addMessage', source, {args = {"[Course-Poursuite]", message}})
    end
end

local function giveReward(source, amount, moneyType)
    moneyType = moneyType or "money"
    
    debugLog("Récompense donnée à " .. source .. ": $" .. amount .. " (" .. moneyType .. ")")
    
    if Config.Framework == "ESX" then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addMoney(moneyType, amount)
        end
    elseif Config.Framework == "QB" then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            Player.Functions.AddMoney(moneyType, amount)
        end
    end
end

-- ════════════════════════════════════════════════════════════════
-- MATCHMAKING
-- ════════════════════════════════════════════════════════════════

local function startInstance(playerA, playerB)
    local instanceId = nextInstanceId
    nextInstanceId = nextInstanceId + 1
    
    debugLog("=== DÉMARRAGE NOUVELLE INSTANCE " .. instanceId .. " ===")
    debugLog("Joueur A: " .. playerA .. " (" .. getPlayerName(playerA) .. ")")
    debugLog("Joueur B: " .. playerB .. " (" .. getPlayerName(playerB) .. ")")
    
    local instance = GameInstance:new(instanceId, playerA, playerB)
    activeInstances[instanceId] = instance
    playerInstances[playerA] = instanceId
    playerInstances[playerB] = instanceId
    
    -- Log Discord
    sendLog("gameStart", 
        "🎮 Nouvelle partie",
        string.format("**Instance:** %d\n**Joueur A:** %s\n**Joueur B:** %s", 
            instanceId, getPlayerName(playerA), getPlayerName(playerB)),
        Config.Webhooks.colors.INFO
    )
    
    -- Notifier les joueurs
    notifyPlayer(playerA, _T("notif_found"), "success")
    notifyPlayer(playerB, _T("notif_found"), "success")
    
    -- Téléporter et démarrer le jeu
    TriggerClientEvent('chase:startGame', playerA, instanceId, "teamA", instance.location)
    TriggerClientEvent('chase:startGame', playerB, instanceId, "teamB", instance.location)
    
    -- Lancer le compte à rebours après un court délai
    SetTimeout(2000, function()
        if activeInstances[instanceId] then
            startCountdown(instanceId)
        end
    end)
end

function startCountdown(instanceId)
    local instance = activeInstances[instanceId]
    if not instance then 
        debugLog("ERREUR: Instance " .. instanceId .. " introuvable pour countdown")
        return 
    end
    
    debugLog("Instance " .. instanceId .. ": Démarrage compte à rebours")
    instance.phase = "COUNTDOWN"
    
    -- Envoyer le compte à rebours aux clients
    TriggerClientEvent('chase:startCountdown', instance.players.teamA.source, Config.Game.countdownDuration)
    TriggerClientEvent('chase:startCountdown', instance.players.teamB.source, Config.Game.countdownDuration)
    
    -- Après le compte à rebours, démarrer la phase de conduite
    SetTimeout(Config.Game.countdownDuration * 1000, function()
        if activeInstances[instanceId] and activeInstances[instanceId].phase == "COUNTDOWN" then
            startDrivingPhase(instanceId)
        end
    end)
end

function startDrivingPhase(instanceId)
    local instance = activeInstances[instanceId]
    if not instance then 
        debugLog("ERREUR: Instance " .. instanceId .. " introuvable pour driving phase")
        return 
    end
    
    debugLog("Instance " .. instanceId .. ": Démarrage phase de conduite")
    instance.phase = "DRIVING"
    
    -- Notifier les clients
    TriggerClientEvent('chase:drivingPhase', instance.players.teamA.source, "teamA")
    TriggerClientEvent('chase:drivingPhase', instance.players.teamB.source, "teamB")
    
    -- Démarrer le timer de drop pour l'équipe A
    instance.dropTimer = SetTimeout(Config.Game.dropTimeLimit * 1000, function()
        if activeInstances[instanceId] and instance.phase == "DRIVING" and not instance.players.teamA.dropped then
            debugLog("Instance " .. instanceId .. ": Team A n'a pas drop à temps!")
            -- L'équipe A n'a pas drop à temps, l'équipe B gagne
            onTeamAFailedToDrop(instanceId)
        end
    end)
    
    debugLog("Timer de drop activé pour " .. Config.Game.dropTimeLimit .. " secondes")
end

-- ════════════════════════════════════════════════════════════════
-- GESTION DES PHASES DE JEU
-- ════════════════════════════════════════════════════════════════

function onTeamAFailedToDrop(instanceId)
    local instance = activeInstances[instanceId]
    if not instance then return end
    
    debugLog("Instance " .. instanceId .. ": Team A a échoué à drop")
    
    -- Annuler le timer
    if instance.dropTimer then
        ClearTimeout(instance.dropTimer)
        instance.dropTimer = nil
    end
    
    -- L'équipe B gagne la manche
    instance.players.teamB.score = instance.players.teamB.score + 1
    
    debugLog("Score mis à jour - TeamA: " .. instance.players.teamA.score .. " | TeamB: " .. instance.players.teamB.score)
    
    notifyPlayer(instance.players.teamA.source, _T("notif_teamA_no_drop"), "error")
    notifyPlayer(instance.players.teamB.source, _T("notif_round_win", instance.currentRound, Config.Game.rounds), "success")
    
    -- Passer à la manche suivante
    SetTimeout(Config.Game.roundTransitionDelay, function()
        nextRound(instanceId)
    end)
end

function startCombatPhase(instanceId)
    local instance = activeInstances[instanceId]
    if not instance then 
        debugLog("ERREUR: Instance " .. instanceId .. " introuvable pour combat phase")
        return 
    end
    
    debugLog("Instance " .. instanceId .. ": Démarrage phase de combat")
    instance.phase = "COMBAT"
    
    -- Utiliser la position de drop de TeamA comme zone de combat
    if instance.players.teamA.dropCoords then
        instance.fightZone = instance.players.teamA.dropCoords
        debugLog("Zone de combat définie à la position de drop: " .. instance.fightZone.x .. ", " .. instance.fightZone.y .. ", " .. instance.fightZone.z)
    else
        -- Fallback: utiliser une zone prédéfinie
        local fightZones = instance.location.fightZones
        instance.fightZone = fightZones[math.random(#fightZones)]
        debugLog("FALLBACK: Zone de combat aléatoire utilisée")
    end
    
    -- Notifier les clients
    TriggerClientEvent('chase:combatPhase', instance.players.teamA.source, instance.fightZone)
    TriggerClientEvent('chase:combatPhase', instance.players.teamB.source, instance.fightZone)
    
    debugLog("Phase de combat lancée - Zone: " .. json.encode(instance.fightZone))
end

function nextRound(instanceId)
    local instance = activeInstances[instanceId]
    if not instance then 
        debugLog("ERREUR: Instance " .. instanceId .. " introuvable pour next round")
        return 
    end
    
    instance.currentRound = instance.currentRound + 1
    
    debugLog("Instance " .. instanceId .. ": Passage à la manche " .. instance.currentRound)
    
    -- Vérifier si le jeu est terminé
    if instance.currentRound > Config.Game.rounds then
        debugLog("Instance " .. instanceId .. ": Toutes les manches terminées, fin du jeu")
        endGame(instanceId)
        return
    end
    
    -- Échanger les équipes
    instance:swapTeams()
    
    -- Réinitialiser l'instance
    instance.phase = "WAITING"
    instance.players.teamA.dropped = false
    instance.players.teamB.dropped = false
    instance.players.teamA.dropCoords = nil
    instance.players.teamB.dropCoords = nil
    instance.fightZone = nil
    
    -- Téléporter à nouveau les joueurs
    TriggerClientEvent('chase:startRound', instance.players.teamA.source, instance.currentRound, "teamA", instance.location)
    TriggerClientEvent('chase:startRound', instance.players.teamB.source, instance.currentRound, "teamB", instance.location)
    
    -- Relancer le compte à rebours
    SetTimeout(2000, function()
        if activeInstances[instanceId] then
            startCountdown(instanceId)
        end
    end)
end

function endGame(instanceId)
    local instance = activeInstances[instanceId]
    if not instance then 
        debugLog("ERREUR: Instance " .. instanceId .. " introuvable pour end game")
        return 
    end
    
    debugLog("=== FIN DE PARTIE INSTANCE " .. instanceId .. " ===")
    instance.phase = "FINISHED"
    
    local scoreA = instance.players.teamA.score
    local scoreB = instance.players.teamB.score
    local winner, loser
    
    if scoreA > scoreB then
        winner = instance.players.teamA.source
        loser = instance.players.teamB.source
        debugLog("Gagnant: " .. winner .. " (TeamA) | Score: " .. scoreA .. "-" .. scoreB)
    else
        winner = instance.players.teamB.source
        loser = instance.players.teamA.source
        debugLog("Gagnant: " .. winner .. " (TeamB) | Score: " .. scoreB .. "-" .. scoreA)
    end
    
    -- Notifier les joueurs
    notifyPlayer(winner, _T("notif_game_win", scoreA, scoreB), "success")
    notifyPlayer(loser, _T("notif_game_lose", scoreA, scoreB), "error")
    
    -- Donner les récompenses
    giveReward(winner, Config.Rewards.winner.money, "money")
    if Config.Rewards.winner.black_money then
        giveReward(winner, Config.Rewards.winner.black_money, "black_money")
    end
    giveReward(loser, Config.Rewards.loser.money, "money")
    
    notifyPlayer(winner, _T("notif_rewards", Config.Rewards.winner.money), "success")
    notifyPlayer(loser, _T("notif_rewards", Config.Rewards.loser.money), "info")
    
    -- Log Discord
    sendLog("gameEnd",
        "🏆 Partie terminée",
        string.format("**Instance:** %d\n**Gagnant:** %s (%d-%d)\n**Perdant:** %s\n**Durée:** %d secondes",
            instanceId, getPlayerName(winner), scoreA, scoreB, getPlayerName(loser), os.time() - instance.startTime),
        Config.Webhooks.colors.SUCCESS
    )
    
    -- Terminer la partie côté client
    TriggerClientEvent('chase:endGame', winner, true, scoreA, scoreB)
    TriggerClientEvent('chase:endGame', loser, false, scoreA, scoreB)
    
    -- Nettoyer l'instance après un délai
    SetTimeout(7000, function()
        if activeInstances[instanceId] then
            debugLog("Nettoyage de l'instance " .. instanceId)
            activeInstances[instanceId]:cleanup()
            activeInstances[instanceId] = nil
        end
    end)
end

-- ════════════════════════════════════════════════════════════════
-- ÉVÉNEMENTS RÉSEAU
-- ════════════════════════════════════════════════════════════════

RegisterNetEvent('chase:joinQueue')
AddEventHandler('chase:joinQueue', function()
    local source = source
    
    debugLog("Joueur " .. source .. " (" .. getPlayerName(source) .. ") tente de rejoindre la file")
    
    -- Vérifier si le joueur est déjà dans une partie
    if playerInstances[source] then
        debugLog("REFUSÉ: Joueur déjà dans une instance")
        notifyPlayer(source, _T("error_already_in_game"), "error")
        return
    end
    
    -- Vérifier si déjà dans la queue
    for _, player in ipairs(matchmakingQueue) do
        if player == source then
            debugLog("REFUSÉ: Joueur déjà dans la file")
            return
        end
    end
    
    -- Vérifier s'il y a déjà quelqu'un dans la file
    if #matchmakingQueue > 0 then
        local opponent = matchmakingQueue[1]
        table.remove(matchmakingQueue, 1)
        
        debugLog("Match trouvé! Joueur " .. source .. " vs Joueur " .. opponent)
        debugLog("File d'attente actuelle: " .. #matchmakingQueue .. " joueurs")
        
        -- Démarrer une partie
        startInstance(opponent, source)
    else
        -- Ajouter à la file d'attente
        table.insert(matchmakingQueue, source)
        notifyPlayer(source, _T("notif_searching"), "info")
        
        -- Envoyer l'état au client
        TriggerClientEvent('chase:queueStatus', source, true)
        
        debugLog("Joueur ajouté à la file. Total en attente: " .. #matchmakingQueue)
    end
end)

RegisterNetEvent('chase:leaveQueue')
AddEventHandler('chase:leaveQueue', function(manualCancel)
    local source = source
    
    debugLog("Joueur " .. source .. " quitte la file" .. (manualCancel and " (annulation manuelle)" or ""))
    
    -- Retirer de la file d'attente
    for i, player in ipairs(matchmakingQueue) do
        if player == source then
            table.remove(matchmakingQueue, i)
            -- Envoyer la raison : "cancelled" si annulation manuelle
            local reason = manualCancel and "cancelled" or nil
            TriggerClientEvent('chase:queueStatus', source, false, reason)
            debugLog("Joueur retiré de la file. Restants: " .. #matchmakingQueue .. " (raison: " .. tostring(reason or "aucune") .. ")")
            break
        end
    end
end)

RegisterNetEvent('chase:playerDropped')
AddEventHandler('chase:playerDropped', function(team, dropCoords)
    local source = source
    local instanceId = playerInstances[source]
    local instance = activeInstances[instanceId]
    
    if not instance then 
        debugLog("ERREUR: Joueur " .. source .. " n'est pas dans une instance valide")
        return 
    end
    
    if instance.phase ~= "DRIVING" and instance.phase ~= "COMBAT" then 
        debugLog("ERREUR: Phase incorrecte pour drop: " .. instance.phase)
        return 
    end
    
    debugLog("Instance " .. instanceId .. ": Joueur " .. source .. " (" .. team .. ") a drop")
    
    if team == "teamA" and not instance.players.teamA.dropped then
        instance.players.teamA.dropped = true
        
        -- Enregistrer la position de drop
        if dropCoords then
            instance.players.teamA.dropCoords = vector3(dropCoords.x, dropCoords.y, dropCoords.z)
            debugLog("Position de drop enregistrée: " .. dropCoords.x .. ", " .. dropCoords.y .. ", " .. dropCoords.z)
        end
        
        -- Annuler le timer de drop
        if instance.dropTimer then
            ClearTimeout(instance.dropTimer)
            instance.dropTimer = nil
            debugLog("Timer de drop annulé")
        end
        
        -- Démarrer la phase de combat
        startCombatPhase(instanceId)
        
    elseif team == "teamB" and instance.players.teamA.dropped and not instance.players.teamB.dropped then
        instance.players.teamB.dropped = true
        debugLog("Team B a rejoint la zone de combat")
    end
end)

RegisterNetEvent('chase:playerDied')
AddEventHandler('chase:playerDied', function(team)
    local source = source
    local instanceId = playerInstances[source]
    local instance = activeInstances[instanceId]
    
    if not instance then 
        debugLog("ERREUR: Joueur " .. source .. " mort mais pas dans une instance")
        return 
    end
    
    if instance.phase ~= "COMBAT" then 
        debugLog("ATTENTION: Joueur mort en phase " .. instance.phase)
        return 
    end
    
    debugLog("Instance " .. instanceId .. ": Joueur " .. source .. " (" .. team .. ") est mort")
    
    -- L'équipe adverse gagne la manche
    if team == "teamA" then
        instance.players.teamB.score = instance.players.teamB.score + 1
        debugLog("Team B gagne la manche! Score: TeamA " .. instance.players.teamA.score .. " - TeamB " .. instance.players.teamB.score)
        notifyPlayer(instance.players.teamB.source, _T("notif_round_win", instance.currentRound, Config.Game.rounds), "success")
        notifyPlayer(instance.players.teamA.source, _T("notif_round_lose", instance.currentRound, Config.Game.rounds), "error")
    else
        instance.players.teamA.score = instance.players.teamA.score + 1
        debugLog("Team A gagne la manche! Score: TeamA " .. instance.players.teamA.score .. " - TeamB " .. instance.players.teamB.score)
        notifyPlayer(instance.players.teamA.source, _T("notif_round_win", instance.currentRound, Config.Game.rounds), "success")
        notifyPlayer(instance.players.teamB.source, _T("notif_round_lose", instance.currentRound, Config.Game.rounds), "error")
    end
    
    -- Passer à la manche suivante
    SetTimeout(Config.Game.roundTransitionDelay, function()
        nextRound(instanceId)
    end)
end)

RegisterNetEvent('chase:vehicleSpawned')
AddEventHandler('chase:vehicleSpawned', function(netId)
    local source = source
    local instanceId = playerInstances[source]
    local instance = activeInstances[instanceId]
    
    if not instance then return end
    
    local vehicle = NetworkGetEntityFromNetworkId(netId)
    table.insert(instance.vehicles, vehicle)
    
    debugLog("Instance " .. instanceId .. ": Véhicule enregistré (NetID: " .. netId .. ")")
end)

-- ════════════════════════════════════════════════════════════════
-- DÉCONNEXION
-- ════════════════════════════════════════════════════════════════

AddEventHandler('playerDropped', function(reason)
    local source = source
    
    debugLog("Joueur déconnecté: " .. source .. " (" .. getPlayerName(source) .. ") - Raison: " .. reason)
    
    -- Retirer de la file d'attente
    for i, player in ipairs(matchmakingQueue) do
        if player == source then
            table.remove(matchmakingQueue, i)
            debugLog("Joueur retiré de la file d'attente")
            break
        end
    end
    
    -- Vérifier si le joueur était dans une instance
    local instanceId = playerInstances[source]
    if instanceId then
        local instance = activeInstances[instanceId]
        if instance then
            debugLog("Instance " .. instanceId .. ": Gestion de la déconnexion")
            
            -- Trouver l'adversaire
            local opponent = nil
            if instance.players.teamA.source == source then
                opponent = instance.players.teamB.source
            else
                opponent = instance.players.teamA.source
            end
            
            -- Notifier l'adversaire
            if opponent then
                notifyPlayer(opponent, "Votre adversaire s'est déconnecté. Vous gagnez par forfait!", "success")
                giveReward(opponent, Config.Rewards.winner.money, "money")
                TriggerClientEvent('chase:endGame', opponent, true, 0, 0)
                debugLog("Adversaire " .. opponent .. " notifié et récompensé")
            end
            
            -- Nettoyer l'instance
            instance:cleanup()
            activeInstances[instanceId] = nil
            debugLog("Instance " .. instanceId .. " nettoyée suite à déconnexion")
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
-- COMMANDES ADMIN
-- ════════════════════════════════════════════════════════════════

RegisterCommand('chase_debug', function(source, args)
    if source == 0 or Config.Debug then
        print("=== DEBUG CHASE MINI-GAME SERVER ===")
        print("File d'attente (" .. #matchmakingQueue .. " joueurs):")
        for i, playerId in ipairs(matchmakingQueue) do
            print("  " .. i .. ". Joueur " .. playerId .. " (" .. getPlayerName(playerId) .. ")")
        end
        
        print("\nInstances actives (" .. #activeInstances .. "):")
        for id, instance in pairs(activeInstances) do
            print("  Instance " .. id .. ":")
            print("    Phase: " .. instance.phase)
            print("    Round: " .. instance.currentRound .. "/" .. Config.Game.rounds)
            print("    TeamA: " .. instance.players.teamA.source .. " (Score: " .. instance.players.teamA.score .. ")")
            print("    TeamB: " .. instance.players.teamB.source .. " (Score: " .. instance.players.teamB.score .. ")")
        end
        
        print("\nJoueurs en instance:")
        for playerId, instId in pairs(playerInstances) do
            print("  Joueur " .. playerId .. " -> Instance " .. instId)
        end
        print("====================================")
    end
end, true)

-- Commande pour forcer la fin d'une partie (admin)
RegisterCommand('chase_end', function(source, args)
    if source == 0 or Config.Debug then
        local instanceId = tonumber(args[1])
        if instanceId and activeInstances[instanceId] then
            debugLog("Fin forcée de l'instance " .. instanceId)
            endGame(instanceId)
        else
            print("Instance invalide")
        end
    end
end, true)

-- Afficher les stats au démarrage
CreateThread(function()
    Wait(1000)
    debugLog("=== SERVEUR CHASE MINI-GAME DÉMARRÉ ===")
    debugLog("Framework: " .. Config.Framework)
    debugLog("Debug activé: " .. tostring(Config.Debug))
    debugLog("Nombre de rounds: " .. Config.Game.rounds)
    debugLog("=======================================")
end)
