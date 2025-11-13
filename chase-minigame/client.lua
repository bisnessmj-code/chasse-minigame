--[[
    Script Client - Mini-jeu Course-Poursuite 1v1
    Gestion de l'interface, du gameplay et des contrôles
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
    
    return blip
end

local function cleanupGame()
    -- Supprimer le véhicule
    if playerState.vehicle and DoesEntityExist(playerState.vehicle) then
        DeleteVehicle(playerState.vehicle)
    end
    
    -- Supprimer le blip de zone
    if zoneBlip and DoesBlipExist(zoneBlip) then
        RemoveBlip(zoneBlip)
        zoneBlip = nil
    end
    
    -- Réinitialiser l'état
    playerState.inGame = false
    playerState.team = nil
    playerState.instanceId = nil
    playerState.phase = nil
    playerState.vehicle = nil
    playerState.fightZone = nil
    playerState.inZone = false
    playerState.currentRound = 1
end

local function spawnVehicle(coords, model, callback)
    local modelHash = GetHashKey(model)
    
    RequestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(100)
    end
    
    local vehicle = CreateVehicle(modelHash, coords.x, coords.y, coords.z, coords.w, true, false)
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, false, true, false)
    SetVehicleDoorsLocked(vehicle, 2)
    
    SetModelAsNoLongerNeeded(modelHash)
    
    if callback then
        callback(vehicle)
    end
    
    return vehicle
end

-- ════════════════════════════════════════════════════════════════
-- NPC ET INTERACTION
-- ════════════════════════════════════════════════════════════════

CreateThread(function()
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
    if playerState.inGame or playerState.inQueue then
        return
    end
    
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "openMenu"
    })
end

function closeLobbyMenu()
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = "closeMenu"
    })
end

RegisterNUICallback('close', function(data, cb)
    closeLobbyMenu()
    cb('ok')
end)

RegisterNUICallback('searchMatch', function(data, cb)
    if not playerState.inGame and not playerState.inQueue then
        TriggerServerEvent('chase:joinQueue')
        playerState.inQueue = true
        
        SendNUIMessage({
            action = "searching"
        })
    end
    cb('ok')
end)

RegisterNUICallback('addBot', function(data, cb)
    -- Fonctionnalité future pour ajouter un bot IA
    if Config.Debug then
        print("Ajout d'un bot - Fonctionnalité en développement")
    end
    cb('ok')
end)

-- ════════════════════════════════════════════════════════════════
-- GESTION DU JEU
-- ════════════════════════════════════════════════════════════════

RegisterNetEvent('chase:queueStatus')
AddEventHandler('chase:queueStatus', function(inQueue)
    playerState.inQueue = inQueue
    
    if not inQueue then
        closeLobbyMenu()
    end
end)

RegisterNetEvent('chase:startGame')
AddEventHandler('chase:startGame', function(instanceId, team, location)
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
    
    -- Spawn du véhicule
    local vehicleModel = Config.VehicleModels[math.random(#Config.VehicleModels)]
    playerState.vehicle = spawnVehicle(spawnData.vehicle, vehicleModel, function(veh)
        -- Envoyer le netId au serveur
        local netId = NetworkGetNetworkIdFromEntity(veh)
        TriggerServerEvent('chase:vehicleSpawned', netId)
        
        -- Placer le joueur dans le véhicule
        TaskWarpPedIntoVehicle(playerPed, veh, -1)
    end)
    
    Wait(500)
    DoScreenFadeIn(500)
end)

RegisterNetEvent('chase:startRound')
AddEventHandler('chase:startRound', function(round, team, location)
    playerState.currentRound = round
    playerState.team = team
    playerState.phase = "WAITING"
    playerState.fightZone = nil
    playerState.inZone = false
    
    -- Nettoyer l'ancien véhicule
    if playerState.vehicle and DoesEntityExist(playerState.vehicle) then
        DeleteVehicle(playerState.vehicle)
    end
    
    if zoneBlip and DoesBlipExist(zoneBlip) then
        RemoveBlip(zoneBlip)
        zoneBlip = nil
    end
    
    -- Téléporter
    local playerPed = PlayerPedId()
    local spawnData = location[team]
    
    DoScreenFadeOut(500)
    Wait(500)
    
    SetEntityCoords(playerPed, spawnData.player.x, spawnData.player.y, spawnData.player.z)
    SetEntityHealth(playerPed, 200)
    SetPedArmour(playerPed, 100)
    
    -- Nouveau véhicule
    local vehicleModel = Config.VehicleModels[math.random(#Config.VehicleModels)]
    playerState.vehicle = spawnVehicle(spawnData.vehicle, vehicleModel, function(veh)
        local netId = NetworkGetNetworkIdFromEntity(veh)
        TriggerServerEvent('chase:vehicleSpawned', netId)
        TaskWarpPedIntoVehicle(playerPed, veh, -1)
    end)
    
    Wait(500)
    DoScreenFadeIn(500)
end)

RegisterNetEvent('chase:startCountdown')
AddEventHandler('chase:startCountdown', function(duration)
    playerState.phase = "COUNTDOWN"
    
    SendNUIMessage({
        action = "startCountdown",
        duration = duration
    })
    
    -- Désactiver les contrôles pendant le compte à rebours
    CreateThread(function()
        local endTime = GetGameTimer() + (duration * 1000)
        
        while GetGameTimer() < endTime do
            Wait(0)
            DisableControlAction(0, 71, true) -- Accélérer
            DisableControlAction(0, 72, true) -- Freiner
            DisableControlAction(0, 24, true) -- Attaque
            DisableControlAction(0, 25, true) -- Viser
        end
    end)
end)

RegisterNetEvent('chase:drivingPhase')
AddEventHandler('chase:drivingPhase', function(team)
    playerState.phase = "DRIVING"
    
    SendNUIMessage({
        action = "showNotification",
        message = team == "teamA" and _T("notif_teamA_drop") or _T("notif_teamB_wait"),
        type = "info"
    })
    
    -- Thread pour détecter la sortie du véhicule (Team A)
    if team == "teamA" then
        CreateThread(function()
            local playerPed = PlayerPedId()
            
            while playerState.phase == "DRIVING" and not playerState.inZone do
                Wait(500)
                
                if not IsPedInAnyVehicle(playerPed, false) then
                    -- Le joueur est sorti du véhicule
                    TriggerServerEvent('chase:playerDropped', team)
                    break
                end
            end
        end)
    end
    
    -- Désactiver le tir en voiture
    CreateThread(function()
        while playerState.phase == "DRIVING" do
            Wait(0)
            DisableControlAction(0, 24, true) -- Attaque
            DisableControlAction(0, 25, true) -- Viser
            DisableControlAction(0, 69, true) -- Viser en véhicule
            DisableControlAction(0, 70, true) -- Tirer en véhicule
        end
    end)
end)

RegisterNetEvent('chase:combatPhase')
AddEventHandler('chase:combatPhase', function(zoneCoords)
    playerState.phase = "COMBAT"
    playerState.fightZone = zoneCoords
    
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
    
    for _, weapon in ipairs(Config.Weapons) do
        GiveWeaponToPed(playerPed, GetHashKey(weapon.name), weapon.ammo, false, false)
    end
    
    -- Thread pour vérifier si le joueur est dans la zone
    CreateThread(function()
        while playerState.phase == "COMBAT" do
            Wait(Config.Game.zoneCheckInterval)
            
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local distance = #(playerCoords - playerState.fightZone)
            local wasInZone = playerState.inZone
            
            playerState.inZone = distance <= Config.Zone.radius
            
            -- Notifier si le joueur entre/sort de la zone
            if playerState.inZone and not wasInZone then
                SendNUIMessage({
                    action = "showNotification",
                    message = _T("notif_in_zone"),
                    type = "success"
                })
            elseif not playerState.inZone and wasInZone then
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
                end
            end
        end
    end)
    
    -- Thread pour dessiner le marker de zone
    CreateThread(function()
        while playerState.phase == "COMBAT" do
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
    end)
    
    -- Vérifier si Team B a rejoint la zone
    if playerState.team == "teamB" then
        CreateThread(function()
            local hasNotified = false
            
            while playerState.phase == "COMBAT" and not hasNotified do
                Wait(500)
                
                local playerPed = PlayerPedId()
                
                if not IsPedInAnyVehicle(playerPed, false) and playerState.inZone then
                    TriggerServerEvent('chase:playerDropped', playerState.team)
                    hasNotified = true
                end
            end
        end)
    end
end)

-- Détection de mort
CreateThread(function()
    while true do
        Wait(1000)
        
        if playerState.inGame and playerState.phase == "COMBAT" then
            local playerPed = PlayerPedId()
            
            if IsEntityDead(playerPed) then
                TriggerServerEvent('chase:playerDied', playerState.team)
                
                -- Attendre le respawn
                while IsEntityDead(playerPed) do
                    Wait(100)
                end
            end
        end
    end
end)

RegisterNetEvent('chase:endGame')
AddEventHandler('chase:endGame', function(won, scoreA, scoreB)
    SendNUIMessage({
        action = "endGame",
        won = won,
        scoreA = scoreA,
        scoreB = scoreB
    })
    
    Wait(3000)
    
    -- Téléporter le joueur au NPC
    local playerPed = PlayerPedId()
    
    DoScreenFadeOut(500)
    Wait(500)
    
    SetEntityCoords(playerPed, Config.NPC.coords.x, Config.NPC.coords.y, Config.NPC.coords.z)
    SetEntityHealth(playerPed, 200)
    SetPedArmour(playerPed, 0)
    RemoveAllPedWeapons(playerPed, true)
    
    Wait(500)
    DoScreenFadeIn(500)
    
    cleanupGame()
end)

-- ════════════════════════════════════════════════════════════════
-- NETTOYAGE À LA DÉCONNEXION
-- ════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    
    if playerState.inQueue then
        TriggerServerEvent('chase:leaveQueue')
    end
    
    cleanupGame()
    
    if npcEntity and DoesEntityExist(npcEntity) then
        DeleteEntity(npcEntity)
    end
end)
