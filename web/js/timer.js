// Rest timer. Stores an absolute end time, so the countdown is computed from
// the wall clock every tick — lock the phone, switch apps, come back, and it
// still shows the truth instead of a timer that quietly stopped.

import { db, saveNow } from './store.js';

let interval = null;
let fired = false;
let audioCtx = null;

function el(id) { return document.getElementById(id); }

export function remainingMs() {
  if (!db.timer) return 0;
  return Math.max(0, db.timer.endsAt - Date.now());
}

export function isRunning() {
  return !!db.timer;
}

export function startTimer(exerciseId, seconds, label) {
  db.timer = {
    exerciseId,
    label: label || '',
    endsAt: Date.now() + seconds * 1000,
    durationSec: seconds,
  };
  fired = false;
  saveNow();
  paint();
  loop();
}

export function addTime(seconds) {
  if (!db.timer) return;
  db.timer.endsAt += seconds * 1000;
  if (remainingMs() > 0) fired = false;
  saveNow();
  paint();
  loop();
}

export function cancelTimer() {
  db.timer = null;
  fired = false;
  saveNow();
  paint();
}

function loop() {
  if (interval) return;
  interval = setInterval(() => {
    if (!db.timer) { clearInterval(interval); interval = null; return; }
    paint();
  }, 250);
}

function fmt(ms) {
  const total = Math.ceil(ms / 1000);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return m + ':' + String(s).padStart(2, '0');
}

function paint() {
  const bar = el('timerbar');
  if (!bar) return;

  if (!db.timer) {
    bar.hidden = true;
    document.body.classList.remove('has-timer');
    return;
  }

  bar.hidden = false;
  document.body.classList.add('has-timer');

  const left = remainingMs();
  const done = left <= 0;
  bar.classList.toggle('done', done);

  el('timer-time').textContent = done ? 'Rest done' : fmt(left);
  el('timer-label').textContent = db.timer.label || '';

  const pct = done ? 100 : 100 - (left / (db.timer.durationSec * 1000)) * 100;
  el('timer-fill').style.width = pct.toFixed(1) + '%';

  if (done && !fired) {
    fired = true;
    alertDone();
  }
}

function alertDone() {
  try { if (navigator.vibrate) navigator.vibrate([200, 100, 200]); } catch (e) { /* no haptics */ }
  beep();
  try {
    if ('Notification' in window && Notification.permission === 'granted') {
      new Notification('Rest done', {
        body: db.timer && db.timer.label ? 'Next set: ' + db.timer.label : 'Next set',
        tag: 'gymlogger-rest',
        silent: false,
      });
    }
  } catch (e) { /* notifications unavailable */ }
}

function beep() {
  try {
    if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    if (audioCtx.state === 'suspended') audioCtx.resume();
    const now = audioCtx.currentTime;
    [0, 0.22].forEach((offset) => {
      const osc = audioCtx.createOscillator();
      const gain = audioCtx.createGain();
      osc.type = 'sine';
      osc.frequency.value = 880;
      gain.gain.setValueAtTime(0.0001, now + offset);
      gain.gain.exponentialRampToValueAtTime(0.4, now + offset + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + offset + 0.18);
      osc.connect(gain).connect(audioCtx.destination);
      osc.start(now + offset);
      osc.stop(now + offset + 0.2);
    });
  } catch (e) { /* audio blocked until a gesture; vibration still fires */ }
}

// Unlock audio on the first tap so the beep works later without a gesture.
export function primeAudio() {
  try {
    if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    if (audioCtx.state === 'suspended') audioCtx.resume();
  } catch (e) { /* ignore */ }
}

export function initTimer() {
  paint();
  if (db.timer) {
    // A timer that expired while we were away should read "done", not re-alert.
    if (remainingMs() <= 0) fired = true;
    loop();
  }
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) paint();
  });
}
