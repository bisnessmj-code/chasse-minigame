// ════════════════════════════════════════════════════════════════
// VARIABLES GLOBALES
// ════════════════════════════════════════════════════════════════

let countdownInterval = null;
let notificationTimeout = null;
let isSearching = false;

// Protection anti-spam
let lastClickTime = 0;
const CLICK_COOLDOWN = 500; // ms

function canClick() {
    const now = Date.now();
    if (now - lastClickTime < CLICK_COOLDOWN) {
        console.log("[CHASE-NUI] Clic ignoré (cooldown)");
        return false;
    }
    lastClickTime = now;
    return true;
}

// ════════════════════════════════════════════════════════════════
// INITIALISATION
// ════════════════════════════════════════════════════════════════

$(document).ready(function() {
    console.log("[CHASE-NUI] Interface initialisée");
    
    // Cacher toutes les interfaces au démarrage
    $('#mainMenu').hide();
    $('#countdown').hide();
    $('#endScreen').hide();
    
    // Event listeners
    $('#closeBtn').click(function() {
        if (!canClick()) return;
        console.log("[CHASE-NUI] Clic sur fermer");
        closeMenu();
    });
    
    $('#searchBtn').click(function() {
        if (!canClick()) return;
        console.log("[CHASE-NUI] Clic sur rechercher");
        $.post('https://chase-minigame/searchMatch', JSON.stringify({}));
        isSearching = true;
    });
    
    $('#cancelSearchBtn').click(function() {
        if (!canClick()) return;
        console.log("[CHASE-NUI] Clic sur annuler recherche");
        $.post('https://chase-minigame/cancelSearch', JSON.stringify({}));
        isSearching = false;
    });
    
    $('#botBtn').click(function() {
        if (!canClick()) return;
        console.log("[CHASE-NUI] Clic sur ajouter bot");
        $.post('https://chase-minigame/addBot', JSON.stringify({}));
    });
    
    // Fermer le menu avec ESC
    $(document).keyup(function(e) {
        if (e.key === "Escape") {
            if (!canClick()) return;
            console.log("[CHASE-NUI] Touche ESC pressée");
            closeMenu();
        }
    });
});

// ════════════════════════════════════════════════════════════════
// GESTION DU MENU
// ════════════════════════════════════════════════════════════════

function openMenu(searchingState = false) {
    console.log("[CHASE-NUI] Ouverture du menu - En recherche: " + searchingState);
    
    $('#mainMenu').fadeIn(300);
    
    if (searchingState) {
        showSearching();
    } else {
        hideSearching();
    }
}

function closeMenu() {
    console.log("[CHASE-NUI] Fermeture du menu");
    $('#mainMenu').fadeOut(300);
    $.post('https://chase-minigame/close', JSON.stringify({}));
    isSearching = false;
}

function showSearching() {
    console.log("[CHASE-NUI] Affichage statut recherche");
    $('#searchBtn').hide();
    $('#searchingStatus').fadeIn(300);
    isSearching = true;
}

function hideSearching() {
    console.log("[CHASE-NUI] Masquage statut recherche");
    $('#searchingStatus').fadeOut(300);
    $('#searchBtn').show();
    isSearching = false;
}

// ════════════════════════════════════════════════════════════════
// COMPTE À REBOURS
// ════════════════════════════════════════════════════════════════

function startCountdown(duration) {
    console.log("[CHASE-NUI] Démarrage compte à rebours: " + duration + "s");
    
    let timeLeft = duration;
    
    $('#countdownNumber').text(timeLeft);
    $('#countdown').fadeIn(300);
    
    // Effacer l'intervalle précédent s'il existe
    if (countdownInterval) {
        clearInterval(countdownInterval);
    }
    
    countdownInterval = setInterval(function() {
        timeLeft--;
        
        if (timeLeft > 0) {
            $('#countdownNumber').text(timeLeft);
            console.log("[CHASE-NUI] Compte à rebours: " + timeLeft);
            
            // Animation de pulsation
            $('#countdownNumber').css('animation', 'none');
            setTimeout(function() {
                $('#countdownNumber').css('animation', 'countdownPulse 1s ease');
            }, 10);
        } else {
            // GO!
            console.log("[CHASE-NUI] GO!");
            $('#countdownNumber').text('GO!');
            $('#countdownText').text('PARTEZ !');
            
            setTimeout(function() {
                $('#countdown').fadeOut(300);
                clearInterval(countdownInterval);
                countdownInterval = null;
            }, 1000);
        }
    }, 1000);
}

// ════════════════════════════════════════════════════════════════
// TIMER DE DROP
// ════════════════════════════════════════════════════════════════

let dropTimerInterval = null;

function startDropTimer(duration) {
    console.log("[CHASE-NUI] Démarrage timer de drop: " + duration + "s");
    
    let timeLeft = duration;
    
    // Afficher le timer
    $('#dropTimer').fadeIn(300);
    $('#timerValue').text(timeLeft + 's');
    $('#dropTimer').removeClass('warning critical');
    
    // Effacer l'intervalle précédent s'il existe
    if (dropTimerInterval) {
        clearInterval(dropTimerInterval);
    }
    
    dropTimerInterval = setInterval(function() {
        timeLeft--;
        
        if (timeLeft > 0) {
            $('#timerValue').text(timeLeft + 's');
            
            // Changer le style selon le temps restant
            if (timeLeft <= 10) {
                $('#dropTimer').removeClass('warning').addClass('critical');
            } else if (timeLeft <= 20) {
                $('#dropTimer').removeClass('critical').addClass('warning');
            }
            
            console.log("[CHASE-NUI] Timer de drop: " + timeLeft + "s");
        } else {
            // Temps écoulé
            console.log("[CHASE-NUI] Timer de drop terminé");
            stopDropTimer();
        }
    }, 1000);
}

function stopDropTimer() {
    console.log("[CHASE-NUI] Arrêt du timer de drop");
    
    if (dropTimerInterval) {
        clearInterval(dropTimerInterval);
        dropTimerInterval = null;
    }
    
    $('#dropTimer').fadeOut(300);
}

// ════════════════════════════════════════════════════════════════
// NOTIFICATIONS
// ════════════════════════════════════════════════════════════════

function showNotification(message, type = 'info', duration = 4000) {
    console.log("[CHASE-NUI] Notification: [" + type + "] " + message);
    
    const notif = $('<div>')
        .addClass('notification')
        .addClass(type)
        .html('<div class="notification-content">' + escapeHtml(message) + '</div>');
    
    $('#notifications').append(notif);
    
    // Retirer la notification après un délai
    setTimeout(function() {
        notif.fadeOut(300, function() {
            $(this).remove();
        });
    }, duration);
}

// ════════════════════════════════════════════════════════════════
// ÉCRAN DE FIN
// ════════════════════════════════════════════════════════════════

function showEndScreen(won, scoreA, scoreB) {
    console.log("[CHASE-NUI] Écran de fin - Victoire: " + won + " | Score: " + scoreA + "-" + scoreB);
    
    const resultText = won ? 'VICTOIRE' : 'DÉFAITE';
    const resultClass = won ? 'victory' : 'defeat';
    const message = won ? 'Félicitations champion !' : 'Vous ferez mieux la prochaine fois !';
    
    $('#endResult')
        .text(resultText)
        .removeClass('victory defeat')
        .addClass(resultClass);
    
    $('#endScore').text(scoreA + ' - ' + scoreB);
    $('#endMessage').text(message);
    
    $('#endScreen').fadeIn(500);
    
    // Cacher automatiquement après 5 secondes
    setTimeout(function() {
        $('#endScreen').fadeOut(500);
        console.log("[CHASE-NUI] Écran de fin fermé");
    }, 5000);
}

// ════════════════════════════════════════════════════════════════
// COMMUNICATION AVEC LUA
// ════════════════════════════════════════════════════════════════

window.addEventListener('message', function(event) {
    const data = event.data;
    console.log("[CHASE-NUI] Message reçu:", data.action);
    
    switch(data.action) {
        case 'openMenu':
            openMenu(data.searching || false);
            break;
            
        case 'closeMenu':
            // Fermeture visuelle uniquement (pas de callback vers Lua)
            console.log("[CHASE-NUI] Fermeture du menu (depuis Lua)");
            $('#mainMenu').fadeOut(300);
            isSearching = false;
            break;
            
        case 'searching':
            showSearching();
            break;
            
        case 'searchCancelled':
            hideSearching();
            showNotification("Recherche annulée", "info");
            break;
            
        case 'startCountdown':
            closeMenu();
            startCountdown(data.duration);
            break;
            
        case 'showNotification':
            showNotification(data.message, data.type || 'info');
            break;
            
        case 'startDropTimer':
            startDropTimer(data.duration);
            break;
            
        case 'stopDropTimer':
            stopDropTimer();
            break;
            
        case 'endGame':
            showEndScreen(data.won, data.scoreA, data.scoreB);
            break;
            
        default:
            console.log("[CHASE-NUI] Action inconnue:", data.action);
    }
});

// ════════════════════════════════════════════════════════════════
// FONCTIONS UTILITAIRES
// ════════════════════════════════════════════════════════════════

function escapeHtml(text) {
    const map = {
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    };
    return text.replace(/[&<>"']/g, function(m) { return map[m]; });
}

// Désactiver le clic droit et le menu contextuel
document.addEventListener('contextmenu', function(e) {
    e.preventDefault();
    return false;
});

// Empêcher la sélection de texte
document.addEventListener('selectstart', function(e) {
    e.preventDefault();
    return false;
});

console.log("[CHASE-NUI] Script chargé et prêt");
