--[[
    Script Client - Mini-jeu Course-Poursuite 1v1
    Gestion de l'interface, du gameplay et des contrôles
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

-- État du joueur
local playerState = {
    inGame = false,
    inQueue = false,
    team = nil,
    instanceId = nil,
    phase = nil,
    vehicle = nil,
    fightZone = nil,
    inZone = false,
    currentRound = 1
}

-- Cache des entités
local npcEntity = nil
local zoneBlip = nil
local zoneMarker = nil

-- Threads actifs à nettoyer
local activeThreads = {
    dropDetection = false,
    disableControls = false,
    zoneCheck = false,
    zoneMarker = false,
    deathDetection = false
}

-- ════════════════════════════════════════════════════════════════
-- FONCTION DE DEBUG
-- ════════════════════════════════════════════════════════════════

local function debugLog(message)
    if Config.Debug then
        print("^3[CHASE-CLIENT DEBUG]^7 " .. message)
    end
end

-- ════════════════════════════════════════════════════════════════
-- FONCTIONS UTILITAIRES
-- ════════════════════════════════════════════════════════════════

local function drawText3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    local camCoords = GetGameplayCamCoords()
    local distance = #(coords - camCoords)
    
    local scale = (1 / distance) * 2
    local fov = (1 / GetGameplayCamFov()) * 100
    scale = scale * fov
    
    if onScreen then
        SetTextScale(0.0 * scale, 0.55 * scale)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextEdge(2, 0, 0, 0, 150)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry("STRING")
        SetTextCentre(1)
        AddTextComponentString(text)
        DrawText(x, y)
    end
end

local function createBlip(coords, sprite, color, scale, text)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite)
    SetBlipColour(blip, color)
    SetBlipScale(blip, scale)
    SetBlipAsShortRange(blip, false)
    
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString(text)
    EndTextCommandSetBlipName(blip)
    
    debugLog("Blip créé aux coords: " .. coords.x .. ", " .. coords.y .. ", " .. coords.z)
    return blip
end

local function cleanupGame()
    debugLog("=== DÉBUT NETTOYAGE COMPLET DU JEU ===")
    
    -- Arrêter tous les threads actifs
    for threadName, _ in pairs(activeThreads) do
        activeThreads[threadName] = false
        debugLog("Thread arrêté: " .. threadName)
    end
    
    -- Supprimer le véhicule
    if playerState.vehicle and DoesEntityExist(playerState.vehicle) then
        DeleteVehicle(playerState.vehicle)
        debugLog("Véhicule supprimé")
    end
    
    -- Supprimer le blip de zone
    if zoneBlip and DoesBlipExist(zoneBlip) then
        RemoveBlip(zoneBlip)
        zoneBlip = nil
        debugLog("Blip de zone supprimé")
    end
    
    -- Retirer toutes les armes
    local playerPed = PlayerPedId()
    RemoveAllPedWeapons(playerPed, true)
    debugLog("Armes retirées")
    
    -- Réinitialiser la santé et l'armure
    SetEntityHealth(playerPed, 200)
    SetPedArmour(playerPed, 0)
    debugLog("Santé et armure réinitialisées")
    
    -- Réinitialiser l'état
    playerState.inGame = false
    playerState.inQueue = false
    playerState.team = nil
    playerState.instanceId = nil
    playerState.phase = nil
    playerState.vehicle = nil
    playerState.fightZone = nil
    playerState.inZone = false
    playerState.currentRound = 1
    
    debugLog("=== NETTOYAGE COMPLET TERMINÉ ===")
end

local function spawnVehicle(coords, model, callback)
    debugLog("Spawn véhicule: " .. model .. " aux coords: " .. coords.x .. ", " .. coords.y)
    
    local modelHash = GetHashKey(model)
    
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(100)
    end
    
    local vehicle = CreateVehicle(modelHash, coords.x, coords.y, coords.z, coords.w, true, false)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleDoorsLocked(vehicle, 1) -- Déverrouillé
    
    SetModelAsNoLongerNeeded(modelHash)
    
    debugLog("Véhicule spawné avec succès, entity ID: " .. vehicle)
    
    if callback then
        callback(vehicle)
    end
    
    return vehicle
end

-- ════════════════════════════════════════════════════════════════
-- NPC ET INTERACTION
-- ════════════════════════════════════════════════════════════════

CreateThread(function()
    debugLog("Création du NPC de lobby")
    
    -- Créer le NPC
    local modelHash = GetHashKey(Config.NPC.model)
    
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(100)
    end
    
    npcEntity = CreatePed(4, modelHash, Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z - 1.0, Config.NPC.coords.w, false, true)
    
    SetEntityHeading(npcEntity, Config.NPC.coords.w)
    FreezeEntityPosition(npcEntity, true)
    SetEntityInvincible(npcEntity, true)
    SetBlockingOfNonTemporaryEvents(npcEntity, true)
    
    SetModelAsNoLongerNeeded(modelHash)
    
    -- Créer un blip pour le NPC
    local blip = AddBlipForCoord(Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z)
    SetBlipSprite(blip, 315)
    SetBlipColour(blip, 5)
    SetBlipScale(blip, 0.8)
    SetBlipAsShortRange(blip, true)
    
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Course-Poursuite 1v1")
    EndTextCommandSetBlipName(blip)
    
    debugLog("NPC créé avec succès")
end)

-- Thread d'interaction avec le NPC
CreateThread(function()
    local sleepTime = 1000
    
    while true do
        Wait(sleepTime)
        
        if not playerState.inGame then
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local npcCoords = vector3(Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z)
            local distance = #(playerCoords - npcCoords)
            
            if distance < 15.0 then
                sleepTime = 0
                
                if distance < Config.NPC.interactionDistance then
                    drawText3D(npcCoords + vector3(0, 0, 1.0), Config.NPC.displayText)
                    
                    if IsControlJustPressed(0, 38) then -- E
                        debugLog("Tentative d'ouverture du menu - inQueue: " .. tostring(playerState.inQueue) .. ", inGame: " .. tostring(playerState.inGame))
                        openLobbyMenu()
                    end
                end
            else
                sleepTime = 1000
            end
        else
            sleepTime = 1000
        end
    end
end)

-- ════════════════════════════════════════════════════════════════
-- INTERFACE NUI
-- ════════════════════════════════════════════════════════════════

function openLobbyMenu()
    debugLog("openLobbyMenu appelé - inGame: " .. tostring(playerState.inGame) .. ", inQueue: " .. tostring(playerState.inQueue))
    
    -- Ne pas bloquer l'ouverture si en queue, mais afficher l'état de recherche
    if playerState.inGame then
        debugLog("Menu bloqué: joueur en partie")
        return
    end
    
    SetNuiFocus(true, true)
    
    if playerState.inQueue then
        debugLog("Ouverture du menu avec état de recherche")
        SendNUIMessage({
            action = "openMenu",
            searching = true
        })
    else
        debugLog("Ouverture du menu normal")
        SendNUIMessage({
            action = "openMenu"
        })
    end
end

function closeLobbyMenu()
    debugLog("Fermeture du menu")
    SetNuiFocus(false, false)
    -- Ne PAS envoyer de message NUI ici pour éviter la boucle infinie
    -- Le JS gère déjà la fermeture visuelle
end

-- Protection anti-spam
local lastCloseCall = 0
local CLOSE_COOLDOWN = 500 -- ms

RegisterNUICallback('close', function(data, cb)
    local now = GetGameTimer()
    if now - lastCloseCall < CLOSE_COOLDOWN then
        debugLog("Callback close ignoré (cooldown)")
        cb('ok')
        return
    end
    lastCloseCall = now
    
    debugLog("NUI Callback: close")
    closeLobbyMenu()
    cb('ok')
end)

local lastSearchCall = 0

RegisterNUICallback('searchMatch', function(data, cb)
    local now = GetGameTimer()
    if now - lastSearchCall < CLOSE_COOLDOWN then
        debugLog("Callback searchMatch ignoré (cooldown)")
        cb('ok')
        return
    end
    lastSearchCall = now
    
    debugLog("NUI Callback: searchMatch - inGame: " .. tostring(playerState.inGame) .. ", inQueue: " .. tostring(playerState.inQueue))
    
    if not playerState.inGame and not playerState.inQueue then
        TriggerServerEvent('chase:joinQueue')
        playerState.inQueue = true
        
        SendNUIMessage({
            action = "searching"
        })
        
        debugLog("Recherche de partie lancée")
    else
        debugLog("Recherche bloquée: déjà en jeu ou en queue")
    end
    cb('ok')
end)

local lastCancelCall = 0

RegisterNUICallback('cancelSearch', function(data, cb)
    local now = GetGameTimer()
    if now - lastCancelCall < CLOSE_COOLDOWN then
        debugLog("Callback cancelSearch ignoré (cooldown)")
        cb('ok')
        return
    end
    lastCancelCall = now
    
    debugLog("NUI Callback: cancelSearch")
    
    if playerState.inQueue then
        TriggerServerEvent('chase:leaveQueue', true) -- true = annulation manuelle
        playerState.inQueue = false
        
        SendNUIMessage({
            action = "searchCancelled"
        })
        
        debugLog("Recherche annulée - Menu reste ouvert")
    end
    cb('ok')
end)

RegisterNUICallback('addBot', function(data, cb)
    debugLog("NUI Callback: addBot - Fonctionnalité en développement")
    cb('ok')
end)

-- ════════════════════════════════════════════════════════════════
-- GESTION DU JEU
-- ════════════════════════════════════════════════════════════════

RegisterNetEvent('chase:queueStatus')
AddEventHandler('chase:queueStatus', function(inQueue, reason)
    debugLog("Événement reçu: chase:queueStatus - " .. tostring(inQueue) .. " (raison: " .. tostring(reason or "aucune") .. ")")
    playerState.inQueue = inQueue
    
    -- Ne fermer le menu que si un match a été trouvé
    -- Si reason = "cancelled", on garde le menu ouvert
    if not inQueue and reason ~= "cancelled" then
        debugLog("Fermeture du menu (match trouvé ou erreur)")
        closeLobbyMenu()
    elseif not inQueue and reason == "cancelled" then
        debugLog("Queue annulée - menu reste ouvert")
    end
end)

RegisterNetEvent('chase:startGame')
AddEventHandler('chase:startGame', function(instanceId, team, location)
    debugLog("=== DÉBUT DE PARTIE ===")
    debugLog("Instance ID: " .. instanceId)
    debugLog("Équipe: " .. team)
    
    playerState.inGame = true
    playerState.instanceId = instanceId
    playerState.team = team
    playerState.inQueue = false
    playerState.currentRound = 1
    
    closeLobbyMenu()
    
    -- Téléporter le joueur
    local playerPed = PlayerPedId()
    local spawnData = location[team]
    
    DoScreenFadeOut(500)
    Wait(500)
    
    SetEntityCoords(playerPed, spawnData.player.x, spawnData.player.y, spawnData.player.z)
    debugLog("Joueur téléporté à: " .. spawnData.player.x .. ", " .. spawnData.player.y)
    
    -- Spawn du véhicule
    local vehicleModel = Config.VehicleModels[math.random(#Config.VehicleModels)]
    debugLog("Spawn véhicule modèle: " .. vehicleModel)
    
    playerState.vehicle = spawnVehicle(spawnData.vehicle, vehicleModel, function(veh)
        -- Envoyer le netId au serveur
        local netId = NetworkGetNetworkIdFromEntity(veh)
        TriggerServerEvent('chase:vehicleSpawned', netId)
        debugLog("NetID véhicule envoyé au serveur: " .. netId)
        
        -- Placer le joueur dans le véhicule
        TaskWarpPedIntoVehicle(playerPed, veh, -1)
        debugLog("Joueur placé dans le véhicule")
    end)
    
    Wait(500)
    DoScreenFadeIn(500)
    
    debugLog("=== PARTIE INITIALISÉE ===")
end)

RegisterNetEvent('chase:startRound')
AddEventHandler('chase:startRound', function(round, team, location)
    debugLog("=== DÉBUT MANCHE " .. round .. " ===")
    debugLog("Équipe: " .. team)
    
    playerState.currentRound = round
    playerState.team = team
    playerState.phase = "WAITING"
    playerState.fightZone = nil
    playerState.inZone = false
    
    -- Arrêter TOUS les threads actifs
    for threadName, _ in pairs(activeThreads) do
        activeThreads[threadName] = false
    end
    debugLog("Tous les threads arrêtés pour nouveau round")
    
    -- Arrêter tous les effets visuels
    SendNUIMessage({
        action = "stopDropTimer"
    })
    
    -- Nettoyer l'ancien véhicule
    if playerState.vehicle and DoesEntityExist(playerState.vehicle) then
        DeleteVehicle(playerState.vehicle)
        debugLog("Ancien véhicule supprimé")
    end
    
    if zoneBlip and DoesBlipExist(zoneBlip) then
        RemoveBlip(zoneBlip)
        zoneBlip = nil
        debugLog("Blip de zone supprimé")
    end
    
    -- Téléporter
    local playerPed = PlayerPedId()
    local spawnData = location[team]
    
    DoScreenFadeOut(500)
    Wait(500)
    
    SetEntityCoords(playerPed, spawnData.player.x, spawnData.player.y, spawnData.player.z)
    SetEntityHealth(playerPed, 200)
    SetPedArmour(playerPed, 100)
    RemoveAllPedWeapons(playerPed, true)
    debugLog("Joueur réinitialisé")
    
    -- Nouveau véhicule
    local vehicleModel = Config.VehicleModels[math.random(#Config.VehicleModels)]
    playerState.vehicle = spawnVehicle(spawnData.vehicle, vehicleModel, function(veh)
        local netId = NetworkGetNetworkIdFromEntity(veh)
        TriggerServerEvent('chase:vehicleSpawned', netId)
        TaskWarpPedIntoVehicle(playerPed, veh, -1)
        debugLog("Nouveau véhicule spawné")
    end)
    
    Wait(500)
    DoScreenFadeIn(500)
end)

RegisterNetEvent('chase:startCountdown')
AddEventHandler('chase:startCountdown', function(duration)
    debugLog("Compte à rebours démarré: " .. duration .. " secondes")
    playerState.phase = "COUNTDOWN"
    
    SendNUIMessage({
        action = "startCountdown",
        duration = duration
    })
    
    -- Désactiver les contrôles pendant le compte à rebours
    activeThreads.disableControls = true
    CreateThread(function()
        local endTime = GetGameTimer() + (duration * 1000)
        
        while GetGameTimer() < endTime and activeThreads.disableControls do
            Wait(0)
            DisableControlAction(0, 71, true) -- Accélérer
            DisableControlAction(0, 72, true) -- Freiner
            DisableControlAction(0, 24, true) -- Attaque
            DisableControlAction(0, 25, true) -- Viser
        end
        
        debugLog("Compte à rebours terminé")
    end)
end)

RegisterNetEvent('chase:drivingPhase')
AddEventHandler('chase:drivingPhase', function(team)
    debugLog("Phase de conduite - Équipe: " .. team)
    playerState.phase = "DRIVING"
    
    SendNUIMessage({
        action = "showNotification",
        message = team == "teamA" and _T("notif_teamA_drop") or _T("notif_teamB_wait"),
        type = "info"
    })
    
    -- Afficher le timer pour Team A
    if team == "teamA" then
        SendNUIMessage({
            action = "startDropTimer",
            duration = Config.Game.dropTimeLimit
        })
        debugLog("Timer de drop démarré: " .. Config.Game.dropTimeLimit .. "s")
    end
    
    -- Thread pour détecter la sortie du véhicule (Team A)
    if team == "teamA" then
        activeThreads.dropDetection = true
        CreateThread(function()
            local playerPed = PlayerPedId()
            
            while playerState.phase == "DRIVING" and not playerState.inZone and activeThreads.dropDetection do
                Wait(500)
                
                if not IsPedInAnyVehicle(playerPed, false) then
                    debugLog("!!! JOUEUR TEAMA A DROP !!!")
                    
                    -- Arrêter le timer
                    SendNUIMessage({
                        action = "stopDropTimer"
                    })
                    
                    -- Obtenir la position actuelle du joueur
                    local dropCoords = GetEntityCoords(playerPed)
                    debugLog("Position de drop: " .. dropCoords.x .. ", " .. dropCoords.y .. ", " .. dropCoords.z)
                    
                    -- Donner une arme immédiatement (Cal50/Sniper)
                    RemoveAllPedWeapons(playerPed, true)
                    Wait(50) -- Petit délai pour être sûr que les armes sont supprimées
                    
                    local weaponHash = GetHashKey("WEAPON_HEAVYSNIPER")
                    GiveWeaponToPed(playerPed, weaponHash, 50, false, true)
                    SetCurrentPedWeapon(playerPed, weaponHash, true)
                    
                    -- Attendre que l'arme soit vraiment équipée
                    local attempts = 0
                    while GetSelectedPedWeapon(playerPed) ~= weaponHash and attempts < 20 do
                        SetCurrentPedWeapon(playerPed, weaponHash, true)
                        Wait(50)
                        attempts = attempts + 1
                    end
                    
                    debugLog("Arme donnée et équipée: WEAPON_HEAVYSNIPER (tentatives: " .. attempts .. ")")
                    
                    -- Envoyer la position de drop au serveur
                    TriggerServerEvent('chase:playerDropped', team, dropCoords)
                    
                    activeThreads.dropDetection = false
                    break
                end
            end
            
            debugLog("Thread de détection de drop terminé")
        end)
    end
    
    -- Désactiver le tir en voiture
    activeThreads.disableControls = true
    CreateThread(function()
        while playerState.phase == "DRIVING" and activeThreads.disableControls do
            Wait(0)
            DisableControlAction(0, 24, true) -- Attaque
            DisableControlAction(0, 25, true) -- Viser
            DisableControlAction(0, 69, true) -- Viser en véhicule
            DisableControlAction(0, 70, true) -- Tirer en véhicule
        end
        
        debugLog("Thread désactivation contrôles terminé")
    end)
end)

RegisterNetEvent('chase:combatPhase')
AddEventHandler('chase:combatPhase', function(zoneCoords)
    debugLog("=== PHASE DE COMBAT ===")
    debugLog("Zone coords: " .. zoneCoords.x .. ", " .. zoneCoords.y .. ", " .. zoneCoords.z)
    
    playerState.phase = "COMBAT"
    playerState.fightZone = zoneCoords
    
    -- Arrêter les threads de la phase précédente
    activeThreads.dropDetection = false
    activeThreads.disableControls = false
    
    -- Créer un blip pour la zone
    zoneBlip = createBlip(zoneCoords, Config.Zone.blipSprite, Config.Zone.blipColor, Config.Zone.blipScale, "Zone de Combat")
    SetBlipRoute(zoneBlip, true)
    
    SendNUIMessage({
        action = "showNotification",
        message = _T("notif_zone_appear"),
        type = "success"
    })
    
    -- Donner des armes au joueur
    local playerPed = PlayerPedId()
    RemoveAllPedWeapons(playerPed, true)
    Wait(100) -- Attendre que les armes soient supprimées
    
    debugLog("Don des armes de combat...")
    for i, weapon in ipairs(Config.Weapons) do
        local weaponHash = GetHashKey(weapon.name)
        GiveWeaponToPed(playerPed, weaponHash, weapon.ammo, false, i == 1) -- Première arme équipée
        debugLog("Arme donnée: " .. weapon.name .. " (" .. weapon.ammo .. " balles)")
    end
    
    -- S'assurer que la première arme est équipée
    if #Config.Weapons > 0 then
        local firstWeaponHash = GetHashKey(Config.Weapons[1].name)
        SetCurrentPedWeapon(playerPed, firstWeaponHash, true)
        debugLog("Première arme équipée: " .. Config.Weapons[1].name)
    end
    
    -- Thread pour vérifier si le joueur est dans la zone
    activeThreads.zoneCheck = true
    CreateThread(function()
        while playerState.phase == "COMBAT" and activeThreads.zoneCheck do
            Wait(Config.Game.zoneCheckInterval)
            
            -- Vérifier que la zone existe avant de calculer
            if not playerState.fightZone then
                debugLog("ATTENTION: fightZone nil dans zoneCheck")
                Wait(1000)
                goto continue
            end
            
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            
            -- Conversion explicite en vector3 pour éviter les erreurs
            local zoneVec = vector3(playerState.fightZone.x, playerState.fightZone.y, playerState.fightZone.z)
            local distance = #(playerCoords - zoneVec)
            local wasInZone = playerState.inZone
            
            playerState.inZone = distance <= Config.Zone.radius
            
            -- Notifier si le joueur entre/sort de la zone
            if playerState.inZone and not wasInZone then
                debugLog("Joueur entre dans la zone")
                SendNUIMessage({
                    action = "showNotification",
                    message = _T("notif_in_zone"),
                    type = "success"
                })
            elseif not playerState.inZone and wasInZone then
                debugLog("Joueur sort de la zone")
                SendNUIMessage({
                    action = "showNotification",
                    message = _T("notif_left_zone"),
                    type = "warning"
                })
            end
            
            -- Appliquer des dégâts si hors zone
            if not playerState.inZone then
                local health = GetEntityHealth(playerPed)
                if health > 100 then
                    SetEntityHealth(playerPed, health - Config.Game.healthPenalty)
                    debugLog("Dégâts hors zone appliqués: -" .. Config.Game.healthPenalty .. " HP")
                end
            end
            
            ::continue::
        end
        
        debugLog("Thread vérification zone terminé")
    end)
    
    -- Thread pour dessiner le marker de zone
    activeThreads.zoneMarker = true
    CreateThread(function()
        while playerState.phase == "COMBAT" and activeThreads.zoneMarker do
            Wait(0)
            
            if playerState.fightZone then
                -- Dessiner le cylindre
                DrawMarker(
                    Config.Zone.markerType,
                    playerState.fightZone.x, playerState.fightZone.y, playerState.fightZone.z - 1.0,
                    0.0, 0.0, 0.0,
                    0.0, 0.0, 0.0,
                    Config.Zone.radius * 2, Config.Zone.radius * 2, Config.Zone.beamHeight,
                    Config.Zone.markerColor.r, Config.Zone.markerColor.g, Config.Zone.markerColor.b, Config.Zone.markerColor.a,
                    false, false, 2, false, nil, nil, false
                )
            end
        end
        
        debugLog("Thread marker zone terminé")
    end)
    
    -- Vérifier si Team B a rejoint la zone
    if playerState.team == "teamB" then
        activeThreads.dropDetection = true
        CreateThread(function()
            local hasNotified = false
            
            while playerState.phase == "COMBAT" and not hasNotified and activeThreads.dropDetection do
                Wait(500)
                
                local playerPed = PlayerPedId()
                
                if not IsPedInAnyVehicle(playerPed, false) and playerState.inZone then
                    debugLog("!!! JOUEUR TEAMB A REJOINT LA ZONE !!!")
                    
                    -- Donner des armes supplémentaires si nécessaire
                    for _, weapon in ipairs(Config.Weapons) do
                        GiveWeaponToPed(playerPed, GetHashKey(weapon.name), weapon.ammo, false, false)
                    end
                    
                    TriggerServerEvent('chase:playerDropped', playerState.team)
                    hasNotified = true
                end
            end
            
            debugLog("Thread TeamB drop zone terminé")
        end)
    end
end)

-- Détection de mort améliorée
CreateThread(function()
    activeThreads.deathDetection = true
    local lastDeathCheck = 0
    
    while true do
        Wait(500) -- Check toutes les 500ms au lieu de 1000ms
        
        if playerState.inGame and playerState.phase == "COMBAT" and activeThreads.deathDetection then
            local playerPed = PlayerPedId()
            
            if IsEntityDead(playerPed) then
                -- Vérifier plusieurs fois pour être sûr
                Wait(100)
                if IsEntityDead(playerPed) then
                    debugLog("!!! JOUEUR MORT !!!")
                    
                    -- Arrêter le timer de drop si actif
                    SendNUIMessage({
                        action = "stopDropTimer"
                    })
                    
                    -- Notifier le serveur une seule fois
                    local now = GetGameTimer()
                    if now - lastDeathCheck > 3000 then -- Cooldown de 3 secondes
                        TriggerServerEvent('chase:playerDied', playerState.team)
                        lastDeathCheck = now
                        debugLog("Mort notifiée au serveur")
                    end
                    
                    -- Attendre le respawn
                    while IsEntityDead(playerPed) do
                        Wait(100)
                    end
                    
                    debugLog("Joueur respawné")
                end
            end
        end
    end
end)

RegisterNetEvent('chase:endGame')
AddEventHandler('chase:endGame', function(won, scoreA, scoreB)
    debugLog("=== FIN DE PARTIE ===")
    debugLog("Résultat: " .. (won and "VICTOIRE" or "DÉFAITE"))
    debugLog("Score: " .. scoreA .. " - " .. scoreB)
    
    -- Arrêter tous les threads
    for threadName, _ in pairs(activeThreads) do
        activeThreads[threadName] = false
    end
    
    -- Arrêter tous les effets visuels
    SendNUIMessage({
        action = "stopDropTimer"
    })
    
    SendNUIMessage({
        action = "endGame",
        won = won,
        scoreA = scoreA,
        scoreB = scoreB
    })
    
    Wait(5000)
    
    -- Téléporter le joueur au NPC
    local playerPed = PlayerPedId()
    
    DoScreenFadeOut(500)
    Wait(500)
    
    SetEntityCoords(playerPed, Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z)
    SetEntityHealth(playerPed, 200)
    SetPedArmour(playerPed, 0)
    RemoveAllPedWeapons(playerPed, true)
    
    debugLog("Joueur téléporté au lobby")
    
    Wait(500)
    DoScreenFadeIn(500)
    
    cleanupGame()
    
    debugLog("=== FIN DE PARTIE COMPLÈTE ===")
end)

-- ════════════════════════════════════════════════════════════════
-- NETTOYAGE À LA DÉCONNEXION
-- ════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    debugLog("Arrêt de la ressource - nettoyage")
    
    if playerState.inQueue then
        TriggerServerEvent('chase:leaveQueue')
    end
    
    cleanupGame()
    
    if npcEntity and DoesEntityExist(npcEntity) then
        DeleteEntity(npcEntity)
    end
end)

-- Commande de debug
if Config.Debug then
    RegisterCommand('chase_debug_client', function()
        print("=== DEBUG CLIENT CHASE ===")
        print("État du joueur:", json.encode(playerState, {indent = true}))
        print("Threads actifs:", json.encode(activeThreads, {indent = true}))
        print("=========================")
    end, false)
end
