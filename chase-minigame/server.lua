--[[
    Script Serveur - Mini-jeu Course-Poursuite 1v1
    Gestion du matchmaking, instances et logique de jeu
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
-- CLASSES ET STRUCTURES
-- ════════════════════════════════════════════════════════════════

local GameInstance = {}
GameInstance.__index = GameInstance

function GameInstance:new(id, playerA, playerB)
    local instance = setmetatable({}, GameInstance)
    
    instance.id = id
    instance.players = {
        teamA = {source = playerA, score = 0, dropped = false},
        teamB = {source = playerB, score = 0, dropped = false}
    }
    instance.currentRound = 1
    instance.phase = "WAITING" -- WAITING, COUNTDOWN, DRIVING, COMBAT, FINISHED
    instance.location = Config.SpawnLocations[1] -- Peut être randomisé
    instance.fightZone = nil
    instance.vehicles = {}
    instance.startTime = os.time()
    instance.dropTimer = nil
    instance.roundTimer = nil
    
    return instance
end

function GameInstance:swapTeams()
    local temp = self.players.teamA
    self.players.teamA = self.players.teamB
    self.players.teamB = temp
    
    -- Réinitialiser les états de drop
    self.players.teamA.dropped = false
    self.players.teamB.dropped = false
end

function GameInstance:cleanup()
    -- Supprimer les véhicules
    for _, vehicle in pairs(self.vehicles) do
        if DoesEntityExist(vehicle) then
            DeleteEntity(vehicle)
        end
    end
    
    -- Annuler les timers
    if self.dropTimer then
        ClearTimeout(self.dropTimer)
    end
    if self.roundTimer then
        ClearTimeout(self.roundTimer)
    end
    
    -- Retirer les joueurs de l'instance
    playerInstances[self.players.teamA.source] = nil
    playerInstances[self.players.teamB.source] = nil
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
    if not instance then return end
    
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
    if not instance then return end
    
    instance.phase = "DRIVING"
    
    -- Notifier les clients
    TriggerClientEvent('chase:drivingPhase', instance.players.teamA.source, "teamA")
    TriggerClientEvent('chase:drivingPhase', instance.players.teamB.source, "teamB")
    
    -- Démarrer le timer de drop pour l'équipe A
    instance.dropTimer = SetTimeout(Config.Game.dropTimeLimit * 1000, function()
        if activeInstances[instanceId] and instance.phase == "DRIVING" and not instance.players.teamA.dropped then
            -- L'équipe A n'a pas drop à temps, l'équipe B gagne
            onTeamAFailedToDrop(instanceId)
        end
    end)
end

-- ════════════════════════════════════════════════════════════════
-- GESTION DES PHASES DE JEU
-- ════════════════════════════════════════════════════════════════

function onTeamAFailedToDrop(instanceId)
    local instance = activeInstances[instanceId]
    if not instance then return end
    
    -- Annuler le timer
    if instance.dropTimer then
        ClearTimeout(instance.dropTimer)
        instance.dropTimer = nil
    end
    
    -- L'équipe B gagne la manche
    instance.players.teamB.score = instance.players.teamB.score + 1
    
    notifyPlayer(instance.players.teamA.source, _T("notif_teamA_no_drop"), "error")
    notifyPlayer(instance.players.teamB.source, _T("notif_round_win", instance.currentRound, Config.Game.rounds), "success")
    
    -- Passer à la manche suivante
    SetTimeout(Config.Game.roundTransitionDelay, function()
        nextRound(instanceId)
    end)
end

function startCombatPhase(instanceId)
    local instance = activeInstances[instanceId]
    if not instance then return end
    
    instance.phase = "COMBAT"
    
    -- Générer une zone de combat aléatoire
    local fightZones = instance.location.fightZones
    instance.fightZone = fightZones[math.random(#fightZones)]
    
    -- Notifier les clients
    TriggerClientEvent('chase:combatPhase', instance.players.teamA.source, instance.fightZone)
    TriggerClientEvent('chase:combatPhase', instance.players.teamB.source, instance.fightZone)
end

function nextRound(instanceId)
    local instance = activeInstances[instanceId]
    if not instance then return end
    
    instance.currentRound = instance.currentRound + 1
    
    -- Vérifier si le jeu est terminé
    if instance.currentRound > Config.Game.rounds then
        endGame(instanceId)
        return
    end
    
    -- Échanger les équipes
    instance:swapTeams()
    
    -- Réinitialiser l'instance
    instance.phase = "WAITING"
    instance.players.teamA.dropped = false
    instance.players.teamB.dropped = false
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
    if not instance then return end
    
    instance.phase = "FINISHED"
    
    local scoreA = instance.players.teamA.score
    local scoreB = instance.players.teamB.score
    local winner, loser
    
    if scoreA > scoreB then
        winner = instance.players.teamA.source
        loser = instance.players.teamB.source
    else
        winner = instance.players.teamB.source
        loser = instance.players.teamA.source
    end
    
    -- Notifier les joueurs
    notifyPlayer(winner, _T("notif_game_win", scoreA, scoreB), "success")
    notifyPlayer(loser, _T("notif_game_lose", scoreA, scoreB), "error")
    
    -- Donner les récompenses
    giveReward(winner, Config.Rewards.winner.money, "money")
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
    
    -- Nettoyer l'instance
    SetTimeout(5000, function()
        if activeInstances[instanceId] then
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
    
    -- Vérifier si le joueur est déjà dans une partie
    if playerInstances[source] then
        notifyPlayer(source, _T("error_already_in_game"), "error")
        return
    end
    
    -- Vérifier s'il y a déjà quelqu'un dans la file
    if #matchmakingQueue > 0 then
        local opponent = matchmakingQueue[1]
        table.remove(matchmakingQueue, 1)
        
        -- Démarrer une partie
        startInstance(opponent, source)
    else
        -- Ajouter à la file d'attente
        table.insert(matchmakingQueue, source)
        notifyPlayer(source, _T("notif_searching"), "info")
        
        -- Envoyer l'état au client
        TriggerClientEvent('chase:queueStatus', source, true)
    end
end)

RegisterNetEvent('chase:leaveQueue')
AddEventHandler('chase:leaveQueue', function()
    local source = source
    
    -- Retirer de la file d'attente
    for i, player in ipairs(matchmakingQueue) do
        if player == source then
            table.remove(matchmakingQueue, i)
            TriggerClientEvent('chase:queueStatus', source, false)
            break
        end
    end
end)

RegisterNetEvent('chase:playerDropped')
AddEventHandler('chase:playerDropped', function(team)
    local source = source
    local instanceId = playerInstances[source]
    local instance = activeInstances[instanceId]
    
    if not instance or instance.phase ~= "DRIVING" then return end
    
    if team == "teamA" and not instance.players.teamA.dropped then
        instance.players.teamA.dropped = true
        
        -- Annuler le timer de drop
        if instance.dropTimer then
            ClearTimeout(instance.dropTimer)
            instance.dropTimer = nil
        end
        
        -- Démarrer la phase de combat
        startCombatPhase(instanceId)
    elseif team == "teamB" and instance.players.teamA.dropped and not instance.players.teamB.dropped then
        instance.players.teamB.dropped = true
    end
end)

RegisterNetEvent('chase:playerDied')
AddEventHandler('chase:playerDied', function(team)
    local source = source
    local instanceId = playerInstances[source]
    local instance = activeInstances[instanceId]
    
    if not instance or instance.phase ~= "COMBAT" then return end
    
    -- L'équipe adverse gagne la manche
    if team == "teamA" then
        instance.players.teamB.score = instance.players.teamB.score + 1
        notifyPlayer(instance.players.teamB.source, _T("notif_round_win", instance.currentRound, Config.Game.rounds), "success")
        notifyPlayer(instance.players.teamA.source, _T("notif_round_lose", instance.currentRound, Config.Game.rounds), "error")
    else
        instance.players.teamA.score = instance.players.teamA.score + 1
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
end)

-- ════════════════════════════════════════════════════════════════
-- DÉCONNEXION
-- ════════════════════════════════════════════════════════════════

AddEventHandler('playerDropped', function(reason)
    local source = source
    
    -- Retirer de la file d'attente
    for i, player in ipairs(matchmakingQueue) do
        if player == source then
            table.remove(matchmakingQueue, i)
            break
        end
    end
    
    -- Vérifier si le joueur était dans une instance
    local instanceId = playerInstances[source]
    if instanceId then
        local instance = activeInstances[instanceId]
        if instance then
            -- Trouver l'adversaire
            local opponent = nil
            if instance.players.teamA.source == source then
                opponent = instance.players.teamB.source
            else
                opponent = instance.players.teamA.source
            end
            
            -- Notifier l'adversaire
            if opponent then
                notifyPlayer(opponent, "Votre adversaire s'est déconnecté. Vous gagnez par forfait.", "success")
                giveReward(opponent, Config.Rewards.winner.money, "money")
                TriggerClientEvent('chase:endGame', opponent, true, 0, 0)
            end
            
            -- Nettoyer l'instance
            instance:cleanup()
            activeInstances[instanceId] = nil
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
-- COMMANDES ADMIN
-- ════════════════════════════════════════════════════════════════

if Config.Debug then
    RegisterCommand('chase_debug', function(source, args)
        print("=== DEBUG CHASE MINI-GAME ===")
        print("File d'attente:", json.encode(matchmakingQueue))
        print("Instances actives:", json.encode(activeInstances))
        print("Joueurs en instance:", json.encode(playerInstances))
    end, true)
end
