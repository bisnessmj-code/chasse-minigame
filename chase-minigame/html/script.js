// ════════════════════════════════════════════════════════════════
// VARIABLES GLOBALES
// ════════════════════════════════════════════════════════════════

let countdownInterval = null;
let notificationTimeout = null;

// ════════════════════════════════════════════════════════════════
// INITIALISATION
// ════════════════════════════════════════════════════════════════

$(document).ready(function() {
    // Cacher toutes les interfaces au démarrage
    $('#mainMenu').hide();
    $('#countdown').hide();
    $('#endScreen').hide();
    
    // Event listeners
    $('#closeBtn').click(function() {
        closeMenu();
    });
    
    $('#searchBtn').click(function() {
        $.post('https://chase-minigame/searchMatch', JSON.stringify({}));
    });
    
    $('#botBtn').click(function() {
        $.post('https://chase-minigame/addBot', JSON.stringify({}));
    });
    
    // Fermer le menu avec ESC
    $(document).keyup(function(e) {
        if (e.key === "Escape") {
            closeMenu();
        }
    });
});

// ════════════════════════════════════════════════════════════════
// GESTION DU MENU
// ════════════════════════════════════════════════════════════════

function openMenu() {
    $('#mainMenu').fadeIn(300);
    $('#searchingStatus').hide();
    $('#searchBtn').show();
}

function closeMenu() {
    $('#mainMenu').fadeOut(300);
    $.post('https://chase-minigame/close', JSON.stringify({}));
}

function showSearching() {
    $('#searchBtn').hide();
    $('#searchingStatus').fadeIn(300);
}

function hideSearching() {
    $('#searchingStatus').fadeOut(300);
    $('#searchBtn').show();
}

// ════════════════════════════════════════════════════════════════
// COMPTE À REBOURS
// ════════════════════════════════════════════════════════════════

function startCountdown(duration) {
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
            
            // Animation de pulsation
            $('#countdownNumber').css('animation', 'none');
            setTimeout(function() {
                $('#countdownNumber').css('animation', 'countdownPulse 1s ease');
            }, 10);
        } else {
            // GO!
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
// NOTIFICATIONS
// ════════════════════════════════════════════════════════════════

function showNotification(message, type = 'info', duration = 4000) {
    const notif = $('<div>')
        .addClass('notification')
        .addClass(type)
        .html('<div class="notification-content">' + message + '</div>');
    
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
    }, 5000);
}

// ════════════════════════════════════════════════════════════════
// COMMUNICATION AVEC LUA
// ════════════════════════════════════════════════════════════════

window.addEventListener('message', function(event) {
    const data = event.data;
    
    switch(data.action) {
        case 'openMenu':
            openMenu();
            break;
            
        case 'closeMenu':
            closeMenu();
            break;
            
        case 'searching':
            showSearching();
            break;
            
        case 'startCountdown':
            closeMenu();
            startCountdown(data.duration);
            break;
            
        case 'showNotification':
            showNotification(data.message, data.type || 'info');
            break;
            
        case 'endGame':
            showEndScreen(data.won, data.scoreA, data.scoreB);
            break;
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
