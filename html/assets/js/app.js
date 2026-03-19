(function () {
  'use strict';

  /* ===== DOM refs ===== */
  const card       = document.getElementById('drift-card');
  const scoreEl    = document.getElementById('score-value');
  const angleEl    = document.getElementById('angle-value');
  const moneyEl    = document.getElementById('money-value');
  const comboRow   = document.getElementById('combo-row');
  const comboVal   = document.getElementById('combo-value');
  const moneyRow   = document.getElementById('money-row');
  const arcFill    = document.getElementById('arc-fill');

  // Combo timer bar
  const comboTimerFill = document.getElementById('combo-timer-fill');

  // Personal best
  const pbContainer = document.getElementById('personal-best');
  const pbValue     = document.getElementById('pb-value');
  const newPbOverlay = document.getElementById('new-pb');
  const newPbScore   = document.getElementById('new-pb-score');

  // Leaderboard
  const lbOverlay = document.getElementById('leaderboard-overlay');
  const lbList    = document.getElementById('lb-list');
  const lbClose   = document.getElementById('lb-close');

  // Session summary
  const sessionOverlay = document.getElementById('session-overlay');
  const sessTotal  = document.getElementById('sess-total');
  const sessBest   = document.getElementById('sess-best');
  const sessCombos = document.getElementById('sess-combos');
  const sessMoney  = document.getElementById('sess-money');
  const sessTime   = document.getElementById('sess-time');
  const sessionCard = document.getElementById('session-card');

  /* ===== Arc geometry ===== */
  const arcLength  = arcFill.getTotalLength();
  arcFill.style.strokeDasharray  = arcLength;
  arcFill.style.strokeDashoffset = arcLength;

  /* ===== State ===== */
  let displayedScore = 0;
  let animFrame      = null;
  let hideTimeout    = null;
  let visible        = false;
  let inVehicle      = false;
  let lastBigTier    = 0;
  let lastCombo      = 0;
  let lastScore      = 0;

  /* ===== Config (updated from Lua) ===== */
  let cfgEnableSounds = true;
  let cfgSoundVolume  = 0.3;
  let cfgShowPB       = true;
  let cfgComboWindow  = 2500;

  /* ===== Sound Manager (Web Audio API) ===== */
  let audioCtx = null;

  function getAudioCtx() {
    if (!audioCtx) {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    return audioCtx;
  }

  function playTone(freq, duration, type, vol) {
    if (!cfgEnableSounds) return;
    try {
      var ctx = getAudioCtx();
      var osc = ctx.createOscillator();
      var gain = ctx.createGain();
      osc.type = type || 'sine';
      osc.frequency.setValueAtTime(freq, ctx.currentTime);
      gain.gain.setValueAtTime((vol || cfgSoundVolume) * 0.5, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + (duration || 0.15));
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime);
      osc.stop(ctx.currentTime + (duration || 0.15));
    } catch (e) { /* silent fail */ }
  }

  function playComboSound(combo) {
    if (!cfgEnableSounds) return;
    // Ascending pitch based on combo
    var baseFreq = 400;
    var freq = baseFreq + (combo - 1) * 80;
    freq = Math.min(freq, 1200);

    if (combo === 5 || combo === 10) {
      // Satisfying "ding" - play a chord
      playTone(freq, 0.3, 'sine', cfgSoundVolume);
      setTimeout(function() { playTone(freq * 1.25, 0.25, 'sine', cfgSoundVolume * 0.7); }, 50);
      setTimeout(function() { playTone(freq * 1.5, 0.2, 'sine', cfgSoundVolume * 0.5); }, 100);
    } else {
      playTone(freq, 0.12, 'square', cfgSoundVolume * 0.4);
    }
  }

  function playMilestoneSound(score) {
    if (!cfgEnableSounds) return;
    // Special chord for big milestones
    var milestones = [2000, 5000, 10000];
    for (var i = milestones.length - 1; i >= 0; i--) {
      if (score >= milestones[i] && lastScore < milestones[i]) {
        var base = 500 + i * 200;
        playTone(base, 0.4, 'sine', cfgSoundVolume);
        setTimeout(function() { playTone(base * 1.25, 0.35, 'sine', cfgSoundVolume * 0.8); }, 60);
        setTimeout(function() { playTone(base * 1.5, 0.3, 'sine', cfgSoundVolume * 0.6); }, 120);
        setTimeout(function() { playTone(base * 2, 0.25, 'triangle', cfgSoundVolume * 0.4); }, 180);
        break;
      }
    }
  }

  /* ===== Helpers ===== */
  function formatNumber(n) {
    return n.toLocaleString('en-US');
  }

  function setArc(angle) {
    const clamped = Math.min(Math.max(angle, 0), 90);
    const ratio   = clamped / 90;
    arcFill.style.strokeDashoffset = arcLength * (1 - ratio);
    angleEl.textContent = Math.round(angle) + '\u00B0';
  }

  function setScoreTier(score) {
    scoreEl.classList.remove('big', 'epic');
    if (score >= 5000) {
      if (lastBigTier < 2) { triggerGlow(); lastBigTier = 2; }
      scoreEl.classList.add('epic');
    } else if (score >= 2000) {
      if (lastBigTier < 1) { triggerGlow(); lastBigTier = 1; }
      scoreEl.classList.add('big');
    }
  }

  function triggerGlow() {
    card.classList.remove('glow');
    void card.offsetWidth;
    card.classList.add('glow');
  }

  function popScore() {
    scoreEl.classList.add('pop');
    setTimeout(function () { scoreEl.classList.remove('pop'); }, 150);
  }

  /* ===== Combo Timer Bar ===== */
  function setComboTimer(ratio) {
    comboTimerFill.style.transform = 'scaleX(' + Math.max(0, Math.min(1, ratio)) + ')';
  }

  /* ===== Animated counter ===== */
  function animateScore(target) {
    if (animFrame) cancelAnimationFrame(animFrame);
    var start     = displayedScore;
    var diff      = target - start;
    var startTime = null;
    var duration  = Math.min(300, Math.max(80, Math.abs(diff) * 0.4));

    function step(ts) {
      if (!startTime) startTime = ts;
      var progress = Math.min((ts - startTime) / duration, 1);
      var eased    = 1 - Math.pow(1 - progress, 3);
      displayedScore = Math.round(start + diff * eased);
      scoreEl.textContent = formatNumber(displayedScore);
      setScoreTier(displayedScore);
      if (progress < 1) {
        animFrame = requestAnimationFrame(step);
      } else {
        displayedScore = target;
        scoreEl.textContent = formatNumber(target);
      }
    }
    animFrame = requestAnimationFrame(step);
  }

  /* ===== Animated counting for session summary ===== */
  function animateCount(el, target, prefix, suffix, duration) {
    prefix = prefix || '';
    suffix = suffix || '';
    duration = duration || 1200;
    var start = 0;
    var startTime = null;
    function step(ts) {
      if (!startTime) startTime = ts;
      var progress = Math.min((ts - startTime) / duration, 1);
      var eased = 1 - Math.pow(1 - progress, 3);
      var current = Math.round(target * eased);
      el.textContent = prefix + formatNumber(current) + suffix;
      if (progress < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }

  /* ===== Show / Hide ===== */
  function showCard() {
    if (hideTimeout) { clearTimeout(hideTimeout); hideTimeout = null; }
    card.classList.remove('hiding');
    card.classList.add('visible');
    visible = true;
    // Hide personal best while drifting
    if (cfgShowPB) pbContainer.classList.remove('visible');
  }

  function hideCard() {
    if (!visible) return;
    card.classList.remove('visible');
    card.classList.add('hiding');
    hideTimeout = setTimeout(function () {
      card.classList.remove('hiding');
      visible = false;
      displayedScore = 0;
      lastBigTier    = 0;
      lastCombo      = 0;
      lastScore      = 0;
      scoreEl.textContent = '0';
      scoreEl.classList.remove('big', 'epic');
      moneyRow.classList.remove('visible');
      comboRow.classList.remove('active');
      setArc(0);
      setComboTimer(0);
      // Show personal best when not drifting (only if still in vehicle)
      if (cfgShowPB && inVehicle) pbContainer.classList.add('visible');
    }, 550);
  }

  /* ===== Leaderboard ===== */
  function buildLeaderboard(entries) {
    lbList.innerHTML = '';
    if (!entries || entries.length === 0) {
      lbList.innerHTML = '<div id="lb-empty">No scores yet. Start drifting!</div>';
      return;
    }
    entries.forEach(function(entry, idx) {
      var rank = entry.rank || (idx + 1);
      var div = document.createElement('div');
      div.className = 'lb-entry';
      var rankClass = rank === 1 ? 'gold' : rank === 2 ? 'silver' : rank === 3 ? 'bronze' : 'normal';
      div.innerHTML =
        '<div class="lb-rank ' + rankClass + '">' + rank + '</div>' +
        '<div class="lb-info">' +
          '<div class="lb-name">' + escapeHtml(entry.name || 'Unknown') + '</div>' +
          '<div class="lb-details">' + escapeHtml(entry.vehicle || '') + ' &middot; ' + escapeHtml(entry.date || '') + '</div>' +
        '</div>' +
        '<div class="lb-score">' + formatNumber(entry.score || 0) + '</div>';
      lbList.appendChild(div);
    });
  }

  function escapeHtml(str) {
    var div = document.createElement('div');
    div.appendChild(document.createTextNode(str));
    return div.innerHTML;
  }

  lbClose.addEventListener('click', function() {
    fetch('https://dei_drift/closeLeaderboard', { method: 'POST', body: JSON.stringify({}) });
  });

  /* ===== Session Summary ===== */
  let sessionDismissTimeout = null;

  function showSessionSummary(data) {
    animateCount(sessTotal, data.totalScore || 0);
    animateCount(sessBest, data.bestDrift || 0);
    animateCount(sessCombos, data.totalCombos || 0);
    animateCount(sessMoney, data.moneyEarned || 0, '$');
    animateCount(sessTime, data.driftTime || 0, '', 's');
    sessionOverlay.classList.add('active');
    // Auto dismiss after 8 seconds
    if (sessionDismissTimeout) clearTimeout(sessionDismissTimeout);
    sessionDismissTimeout = setTimeout(hideSessionSummary, 8000);
  }

  function hideSessionSummary() {
    sessionOverlay.classList.remove('active');
    if (sessionDismissTimeout) { clearTimeout(sessionDismissTimeout); sessionDismissTimeout = null; }
  }

  sessionCard.addEventListener('click', hideSessionSummary);

  /* ===== New PB animation ===== */
  let newPbTimeout = null;

  function showNewPB(score) {
    newPbScore.textContent = formatNumber(score);
    newPbOverlay.classList.add('active');
    if (newPbTimeout) clearTimeout(newPbTimeout);
    newPbTimeout = setTimeout(function() {
      newPbOverlay.classList.remove('active');
    }, 3000);
    // Play special sound
    if (cfgEnableSounds) {
      playTone(600, 0.2, 'sine', cfgSoundVolume);
      setTimeout(function() { playTone(800, 0.2, 'sine', cfgSoundVolume); }, 100);
      setTimeout(function() { playTone(1000, 0.3, 'sine', cfgSoundVolume); }, 200);
      setTimeout(function() { playTone(1200, 0.4, 'triangle', cfgSoundVolume * 0.6); }, 300);
    }
  }

  // ===== PREVIEW / DEMO MODE =====
  var IS_BROWSER = !window.invokeNative;
  if (IS_BROWSER) {
    document.addEventListener('DOMContentLoaded', function () {
      document.body.style.visibility = 'visible';
      document.body.setAttribute('data-theme', 'dark');

      setTimeout(function () {
        // Show drift card with demo data
        window.postMessage({ type: 'configUpdate', enableSounds: false, showPersonalBest: true });
        window.postMessage({ type: 'personalBest', score: 8500 });
        window.postMessage({ type: 'driftUpdate', score: 3500, angle: 45, combo: 3, comboTimerRatio: 0.6 });
      }, 300);
    });
  }

  /* ===== NUI Message Handler ===== */
  window.addEventListener('message', function (e) {
    var data = e.data;

    switch (data.type) {
      case 'configUpdate':
        cfgEnableSounds = data.enableSounds !== false;
        cfgSoundVolume = data.soundVolume || 0.3;
        cfgShowPB = data.showPersonalBest !== false;
        cfgComboWindow = data.comboWindow || 2500;
        break;

      case 'driftUpdate':
        showCard();
        animateScore(data.score || 0);
        setArc(data.angle || 0);

        // Combo timer
        if (data.comboTimerRatio !== undefined) {
          setComboTimer(data.comboTimerRatio);
        } else {
          setComboTimer(1);
        }

        // Combo
        if (data.combo && data.combo > 1) {
          comboRow.classList.add('active');
          comboVal.textContent = 'x' + data.combo;
          // Play combo sound when combo increases
          if (data.combo > lastCombo) {
            playComboSound(data.combo);
          }
        } else {
          comboRow.classList.remove('active');
        }
        lastCombo = data.combo || 0;

        // Score milestone sounds
        playMilestoneSound(data.score || 0);
        lastScore = data.score || 0;

        // Pop on significant jumps
        if (data.score - displayedScore > 200) popScore();
        break;

      case 'comboTimer':
        if (data.comboTimerRatio !== undefined) {
          setComboTimer(data.comboTimerRatio);
        }
        break;

      case 'driftEnd':
        if (data.money && data.money > 0) {
          moneyRow.classList.add('visible');
          moneyEl.textContent = '$' + formatNumber(data.money);
        }
        setTimeout(hideCard, 800);
        break;

      case 'driftHide':
        inVehicle = false;
        hideCard();
        pbContainer.classList.remove('visible');
        break;

      case 'personalBest':
        inVehicle = true;
        if (cfgShowPB && data.score > 0) {
          pbValue.textContent = formatNumber(data.score);
          pbContainer.classList.add('visible');
        }
        break;

      case 'newPersonalBest':
        if (cfgShowPB) {
          pbValue.textContent = formatNumber(data.score);
          showNewPB(data.score);
        }
        break;

      case 'showLeaderboard':
        // Request leaderboard data from client
        fetch('https://dei_drift/requestLeaderboard', { method: 'POST', body: JSON.stringify({}) })
          .then(function(resp) { return resp.json(); })
          .then(function(entries) {
            buildLeaderboard(entries);
            lbOverlay.classList.add('active');
          })
          .catch(function() {
            buildLeaderboard([]);
            lbOverlay.classList.add('active');
          });
        break;

      case 'hideLeaderboard':
        lbOverlay.classList.remove('active');
        break;

      case 'sessionSummary':
        showSessionSummary(data);
        break;

      case 'setTheme':
        document.body.setAttribute('data-theme', data.theme || 'dark');
        if (data.lightMode) {
          document.body.classList.add('light-mode');
        } else {
          document.body.classList.remove('light-mode');
        }
        break;
    }
  });
})();
