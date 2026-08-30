import {
  db, save, saveNow, uid, exercise, restSecFor, incrementFor,
  activeSession, finishedSessions, lastEntryFor, suggestionFor,
  startSession, finishSession, discardSession, deleteSession,
  buildEntry, toNum, exportJSON,
} from './store.js';
import { startTimer, cancelTimer, addTime, initTimer, primeAudio } from './timer.js';
import { lineChart } from './chart.js';

const app = document.getElementById('app');

const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => (
  { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
));

const nav = (hash) => { location.hash = hash; };

/* ---------- formatting ---------- */

const fmtDate = (t) => new Date(t).toLocaleDateString(undefined, { weekday: 'short', day: 'numeric', month: 'short' });
const fmtDateLong = (t) => new Date(t).toLocaleDateString(undefined, { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });
const fmtTime = (t) => new Date(t).toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit' });

function fmtDuration(ms) {
  const mins = Math.round(ms / 60000);
  if (mins < 60) return mins + ' min';
  return Math.floor(mins / 60) + 'h ' + (mins % 60) + 'm';
}

function num(v) {
  const n = toNum(v);
  return n === null ? '' : String(Math.round(n * 100) / 100);
}

/* ---------- routing ---------- */

function currentRoute() {
  const raw = location.hash.replace(/^#\/?/, '');
  const parts = raw.split('/').filter(Boolean);
  return { name: parts[0] || 'home', args: parts.slice(1) };
}

let lastRouteKey = '';

function render() {
  const route = currentRoute();
  const key = route.name + '/' + route.args.join('/');
  const sameScreen = key === lastRouteKey;
  const scroll = window.scrollY;

  let html = '';
  switch (route.name) {
    case 'session': html = screenSession(); break;
    case 'history': html = route.args[0] ? screenSessionDetail(route.args[0]) : screenHistory(); break;
    case 'progress': html = screenProgress(route.args[0]); break;
    case 'settings': html = screenSettings(); break;
    case 'template': html = screenTemplate(route.args[0]); break;
    case 'exercise': html = screenExercise(route.args[0], route.args[1]); break;
    case 'pick': html = screenPick(route.args[0], route.args[1]); break;
    default: html = screenHome();
  }

  app.innerHTML = html;
  lastRouteKey = key;
  syncTabs(route.name);

  // Ticking a set re-renders the session screen; jumping to the top mid-workout
  // would be maddening, so hold the scroll position when the screen is the same.
  window.scrollTo(0, sameScreen ? scroll : 0);
}

function syncTabs(name) {
  const map = { home: 'home', history: 'history', progress: 'progress', settings: 'settings' };
  const active = map[name] || (name === 'template' || name === 'exercise' || name === 'pick' ? 'settings' : 'home');
  document.querySelectorAll('.tab').forEach((t) => {
    t.classList.toggle('on', t.dataset.tab === active);
  });
  document.body.classList.toggle('in-session', name === 'session');
}

/* ---------- home ---------- */

function screenHome() {
  const active = activeSession();
  const templates = Object.values(db.templates);
  const recent = finishedSessions().slice(0, 5);

  let html = '<header class="top"><h1>GymLogger</h1></header><div class="pad">';

  if (active) {
    const doneSets = active.entries.reduce((n, e) => n + e.sets.filter((s) => s.done).length, 0);
    html += `<button class="big primary" data-act="resume">
      <span class="big-title">Resume ${esc(active.name)}</span>
      <span class="big-sub">${doneSets} set${doneSets === 1 ? '' : 's'} done · started ${fmtTime(active.startedAt)}</span>
    </button>`;
  } else if (templates.length) {
    templates.forEach((t, i) => {
      const count = t.items.length;
      html += `<button class="big ${i === 0 ? 'primary' : ''}" data-act="start" data-id="${t.id}">
        <span class="big-title">Start ${esc(t.name)}</span>
        <span class="big-sub">${count} exercise${count === 1 ? '' : 's'}</span>
      </button>`;
    });
  } else {
    html += '<p class="empty">No workout templates yet. Create one in Settings.</p>';
  }

  html += '<h2>Recent sessions</h2>';
  if (!recent.length) {
    html += '<p class="empty">Nothing logged yet. Your first session becomes the baseline for everything after it.</p>';
  } else {
    html += '<ul class="list">';
    recent.forEach((s) => { html += sessionRow(s); });
    html += '</ul>';
    if (finishedSessions().length > recent.length) {
      html += '<button class="ghost wide" data-act="go" data-to="history">See all history</button>';
    }
  }

  return html + '</div>';
}

function sessionRow(s) {
  const sets = s.entries.reduce((n, e) => n + e.sets.filter((x) => x.done).length, 0);
  const exs = s.entries.filter((e) => e.sets.some((x) => x.done)).length;
  return `<li><button class="row" data-act="go" data-to="history/${s.id}">
    <span class="row-main">${esc(fmtDate(s.startedAt))}</span>
    <span class="row-sub">${esc(s.name)} · ${exs} exercises · ${sets} sets</span>
    <span class="chev">›</span>
  </button></li>`;
}

/* ---------- active session ---------- */

function screenSession() {
  const s = activeSession();
  if (!s) {
    return '<header class="top"><h1>No active session</h1></header><div class="pad"><p class="empty">Start one from Home.</p><button class="ghost wide" data-act="go" data-to="home">Go home</button></div>';
  }

  let html = `<header class="top sticky">
    <div class="top-row">
      <div>
        <h1>${esc(s.name)}</h1>
        <p class="sub" id="elapsed">${fmtDuration(Date.now() - s.startedAt)}</p>
      </div>
      <button class="finish" data-act="finish">Finish</button>
    </div>
  </header><div class="pad">`;

  s.entries.forEach((entry, ei) => { html += exerciseCard(entry, ei, s); });

  html += `<button class="ghost wide" data-act="go" data-to="pick/session">+ Add exercise to today</button>
    <button class="ghost wide danger" data-act="discard">Discard this session</button>
  </div>`;

  return html;
}

function exerciseCard(entry, ei, session) {
  const last = lastEntryFor(entry.exerciseId, session.id);
  const doneCount = entry.sets.filter((s) => s.done).length;
  const complete = doneCount === entry.sets.length && entry.sets.length > 0;

  let html = `<section class="card ${complete ? 'complete' : ''}" data-ei="${ei}">
    <div class="card-head">
      <button class="card-title" data-act="go" data-to="exercise/${entry.exerciseId}/session">
        <span class="ex-name">${esc(entry.name)}</span>
        <span class="ex-meta">${entry.sets.length} × ${esc(entry.target === null || entry.target === undefined ? '—' : entry.target)} · rest ${restSecFor(entry.exerciseId)}s</span>
      </button>
      <span class="badge">${doneCount}/${entry.sets.length}</span>
    </div>`;

  html += `<input class="note" data-bind="note" data-ei="${ei}" value="${esc(entry.note)}"
    placeholder="Machine settings (e.g. seat 4, handles 2)" enterkeyhint="done">`;

  if (entry.suggested && !complete) {
    const sug = suggestionFor(entry.exerciseId, session.id);
    html += `<div class="suggest">
      <span>Hit every rep last time — try <b>${num(sug.weight)} kg</b>.</span>
      <button class="chip" data-act="ignore-suggest" data-ei="${ei}">Keep ${num(sug.lastWeight)}</button>
    </div>`;
  }

  html += '<div class="sets">';
  entry.sets.forEach((set, si) => {
    const lastSet = last && last.entry.sets[si];
    const lastTxt = lastSet
      ? `${num(lastSet.weight) === '' ? '—' : num(lastSet.weight) + 'kg'} × ${num(lastSet.reps) || '—'}`
      : '—';

    html += `<div class="set ${set.done ? 'done' : ''}">
      <span class="set-n">${si + 1}</span>
      <span class="last" title="Last session">${esc(lastTxt)}</span>
      <input class="field" inputmode="decimal" data-bind="set" data-ei="${ei}" data-si="${si}" data-field="weight"
        value="${esc(set.weight)}" placeholder="kg" aria-label="Set ${si + 1} weight in kg">
      <input class="field" inputmode="numeric" data-bind="set" data-ei="${ei}" data-si="${si}" data-field="reps"
        value="${esc(set.reps)}" placeholder="reps" aria-label="Set ${si + 1} reps">
      <button class="tick" data-act="tick" data-ei="${ei}" data-si="${si}"
        aria-label="${set.done ? 'Mark set ' + (si + 1) + ' not done' : 'Mark set ' + (si + 1) + ' done and start rest'}">
        ${set.done ? '✓' : ''}
      </button>
    </div>`;
  });
  html += '</div>';

  html += `<div class="card-foot">
    <button class="chip" data-act="add-set" data-ei="${ei}">+ Set</button>
    <button class="chip" data-act="del-set" data-ei="${ei}">− Set</button>
    <button class="chip" data-act="rest-now" data-ei="${ei}">Rest</button>
    <button class="chip danger" data-act="drop-ex" data-ei="${ei}">Remove</button>
  </div></section>`;

  return html;
}

/* ---------- history ---------- */

function screenHistory() {
  const list = finishedSessions();
  let html = '<header class="top"><h1>History</h1></header><div class="pad">';
  if (!list.length) {
    html += '<p class="empty">No finished sessions yet.</p>';
  } else {
    html += '<ul class="list">';
    list.forEach((s) => { html += sessionRow(s); });
    html += '</ul>';
  }
  return html + '</div>';
}

function screenSessionDetail(id) {
  const s = db.sessions.find((x) => x.id === id);
  if (!s) return '<header class="top"><h1>Not found</h1></header><div class="pad"><button class="ghost wide" data-act="go" data-to="history">Back to history</button></div>';

  const si = db.sessions.indexOf(s);
  let html = `<header class="top">
    <button class="back" data-act="go" data-to="history">‹ History</button>
    <h1>${esc(fmtDateLong(s.startedAt))}</h1>
    <p class="sub">${esc(s.name)} · ${fmtTime(s.startedAt)}${s.finishedAt ? ' · ' + fmtDuration(s.finishedAt - s.startedAt) : ' · in progress'}</p>
  </header><div class="pad">`;

  s.entries.forEach((entry, ei) => {
    const worked = entry.sets.filter((x) => x.done);
    html += `<section class="card">
      <div class="card-head"><div class="card-title"><span class="ex-name">${esc(entry.name)}</span>
      ${entry.note ? `<span class="ex-meta">${esc(entry.note)}</span>` : ''}</div></div>`;
    if (!worked.length) {
      html += '<p class="empty small">Not logged</p>';
    } else {
      html += '<div class="sets">';
      entry.sets.forEach((set, k) => {
        if (!set.done) return;
        html += `<div class="set">
          <span class="set-n">${k + 1}</span>
          <span class="last"></span>
          <input class="field" inputmode="decimal" data-bind="hist" data-sid="${si}" data-ei="${ei}" data-si="${k}" data-field="weight" value="${esc(set.weight)}" placeholder="kg" aria-label="Weight">
          <input class="field" inputmode="numeric" data-bind="hist" data-sid="${si}" data-ei="${ei}" data-si="${k}" data-field="reps" value="${esc(set.reps)}" placeholder="reps" aria-label="Reps">
          <span class="tick done-static">✓</span>
        </div>`;
      });
      html += '</div>';
    }
    html += '</section>';
  });

  html += `<button class="ghost wide danger" data-act="del-session" data-id="${s.id}">Delete this session</button></div>`;
  return html;
}

/* ---------- progress ---------- */

function progressSeries(exId) {
  const out = [];
  finishedSessions().slice().reverse().forEach((s) => {
    const e = s.entries.find((x) => x.exerciseId === exId);
    if (!e) return;
    const done = e.sets.filter((x) => x.done);
    if (!done.length) return;
    const weights = done.map((x) => toNum(x.weight)).filter((w) => w !== null);
    const reps = done.map((x) => toNum(x.reps)).filter((r) => r !== null);
    out.push({
      t: s.startedAt,
      weight: weights.length ? Math.max(...weights) : null,
      reps: reps.length ? Math.max(...reps) : null,
      sets: done.length,
    });
  });
  return out;
}

function screenProgress(exId) {
  const exs = Object.values(db.exercises);
  const withData = exs.filter((e) => progressSeries(e.id).length > 0);
  const chosen = exId && db.exercises[exId] ? exId : (withData[0] ? withData[0].id : (exs[0] ? exs[0].id : null));

  let html = '<header class="top"><h1>Progress</h1></header><div class="pad">';

  if (!chosen) return html + '<p class="empty">No exercises yet.</p></div>';

  html += '<div class="chips scroll-x">';
  exs.forEach((e) => {
    html += `<button class="chip ${e.id === chosen ? 'on' : ''}" data-act="go" data-to="progress/${e.id}">${esc(e.name)}</button>`;
  });
  html += '</div>';

  const series = progressSeries(chosen);
  // Weight is the point of the chart, but bodyweight work (the plank) never has
  // one — fall back to reps so the screen is still useful there.
  const hasWeight = series.some((p) => p.weight !== null);
  const points = series
    .filter((p) => (hasWeight ? p.weight !== null : p.reps !== null))
    .map((p) => ({
      t: p.t,
      v: hasWeight ? p.weight : p.reps,
      label: `${fmtDate(p.t)}: ${hasWeight ? p.weight + ' kg' : p.reps + ' reps'}`,
    }));

  html += `<section class="card">
    <p class="chart-title">${esc(db.exercises[chosen].name)} — ${hasWeight ? 'top set (kg)' : 'top set (reps)'}</p>
    ${lineChart(points, { aria: db.exercises[chosen].name + ' over time' })}
  </section>`;

  if (series.length) {
    html += '<ul class="list">';
    series.slice().reverse().forEach((p) => {
      html += `<li><div class="row static">
        <span class="row-main">${esc(fmtDate(p.t))}</span>
        <span class="row-sub">${p.weight !== null ? p.weight + ' kg' : 'bodyweight'} · ${p.reps !== null ? p.reps + ' reps' : ''} · ${p.sets} sets</span>
      </div></li>`;
    });
    html += '</ul>';
  }

  return html + '</div>';
}

/* ---------- settings ---------- */

function screenSettings() {
  const canNotify = 'Notification' in window;
  const perm = canNotify ? Notification.permission : 'unsupported';

  let html = '<header class="top"><h1>Settings</h1></header><div class="pad">';

  html += '<h2>Workouts</h2><ul class="list">';
  Object.values(db.templates).forEach((t) => {
    html += `<li><button class="row" data-act="go" data-to="template/${t.id}">
      <span class="row-main">${esc(t.name)}</span>
      <span class="row-sub">${t.items.length} exercises</span>
      <span class="chev">›</span>
    </button></li>`;
  });
  html += '</ul><button class="ghost wide" data-act="new-template">+ New workout</button>';

  html += `<h2>Defaults</h2>
    <label class="field-row"><span>Rest timer (seconds)</span>
      <input class="field wide-field" inputmode="numeric" data-bind="setting" data-key="defaultRestSec" value="${esc(db.settings.defaultRestSec)}"></label>
    <label class="field-row"><span>Weight increase step (kg)</span>
      <input class="field wide-field" inputmode="decimal" data-bind="setting" data-key="defaultIncrement" value="${esc(db.settings.defaultIncrement)}"></label>`;

  html += '<h2>Rest alerts</h2>';
  if (perm === 'granted') {
    html += '<p class="hint">Notifications on. The timer also vibrates and beeps.</p>';
  } else if (perm === 'denied') {
    html += '<p class="hint">Notifications blocked in your browser settings. The timer still vibrates and beeps while the app is open.</p>';
  } else if (perm === 'unsupported') {
    html += '<p class="hint">This browser has no notifications. The timer still vibrates and beeps while the app is open.</p>';
  } else {
    html += '<button class="ghost wide" data-act="ask-notify">Enable rest-finished alerts</button>';
  }

  html += `<h2>Backup</h2>
    <p class="hint">Exports everything — exercises, workouts and every session — as a JSON file.</p>
    <button class="ghost wide" data-act="export">Export all data (JSON)</button>
    <p class="hint version">All data lives in this browser only. Clearing site data erases it, so export now and then.</p>`;

  return html + '</div>';
}

/* ---------- template editor ---------- */

function screenTemplate(id) {
  const t = db.templates[id];
  if (!t) return '<header class="top"><h1>Not found</h1></header><div class="pad"><button class="ghost wide" data-act="go" data-to="settings">Back</button></div>';

  let html = `<header class="top">
    <button class="back" data-act="go" data-to="settings">‹ Settings</button>
    <h1>Edit workout</h1>
  </header><div class="pad">
    <label class="field-row"><span>Name</span>
      <input class="field wide-field" data-bind="tpl-name" data-id="${t.id}" value="${esc(t.name)}"></label>
    <h2>Exercises</h2>`;

  if (!t.items.length) html += '<p class="empty">No exercises yet.</p>';

  t.items.forEach((item, i) => {
    const ex = exercise(item.exerciseId);
    html += `<section class="card">
      <div class="card-head">
        <button class="card-title" data-act="go" data-to="exercise/${item.exerciseId}/template/${t.id}">
          <span class="ex-name">${esc(ex ? ex.name : 'Missing exercise')}</span>
          <span class="ex-meta">rest ${ex ? restSecFor(item.exerciseId) : '—'}s · +${ex ? incrementFor(item.exerciseId) : '—'} kg</span>
        </button>
      </div>
      <div class="grid2">
        <label class="field-row"><span>Sets</span>
          <input class="field" inputmode="numeric" data-bind="tpl-item" data-id="${t.id}" data-i="${i}" data-field="sets" value="${esc(item.sets)}"></label>
        <label class="field-row"><span>Target reps</span>
          <input class="field" inputmode="numeric" data-bind="tpl-item" data-id="${t.id}" data-i="${i}" data-field="target" value="${esc(item.target)}"></label>
      </div>
      <div class="card-foot">
        <button class="chip" data-act="move-up" data-id="${t.id}" data-i="${i}" ${i === 0 ? 'disabled' : ''}>▲ Up</button>
        <button class="chip" data-act="move-down" data-id="${t.id}" data-i="${i}" ${i === t.items.length - 1 ? 'disabled' : ''}>▼ Down</button>
        <button class="chip danger" data-act="tpl-remove" data-id="${t.id}" data-i="${i}">Remove</button>
      </div>
    </section>`;
  });

  html += `<button class="ghost wide" data-act="go" data-to="pick/template/${t.id}">+ Add exercise</button>`;
  if (Object.keys(db.templates).length > 1) {
    html += `<button class="ghost wide danger" data-act="del-template" data-id="${t.id}">Delete this workout</button>`;
  }
  return html + '</div>';
}

/* ---------- exercise editor ---------- */

function screenExercise(id, from) {
  const ex = exercise(id);
  const back = from === 'session' ? 'session' : (from === 'template' ? 'template/' + currentRoute().args[2] : 'settings');
  const backLabel = from === 'session' ? '‹ Workout' : from === 'template' ? '‹ Workout edit' : '‹ Settings';

  if (!ex) return '<header class="top"><h1>Not found</h1></header><div class="pad"></div>';

  return `<header class="top">
    <button class="back" data-act="go" data-to="${back}">${backLabel}</button>
    <h1>Edit exercise</h1>
  </header><div class="pad">
    <label class="field-row"><span>Name</span>
      <input class="field wide-field" data-bind="ex" data-id="${ex.id}" data-field="name" value="${esc(ex.name)}"></label>
    <label class="field-row col"><span>Machine settings note</span>
      <input class="field wide-field" data-bind="ex" data-id="${ex.id}" data-field="notes" value="${esc(ex.notes)}"
        placeholder="e.g. seat 4, handles 2"></label>
    <p class="hint">The note shows on this exercise every session.</p>
    <label class="field-row"><span>Rest timer (sec)</span>
      <input class="field" inputmode="numeric" data-bind="ex" data-id="${ex.id}" data-field="restSec" value="${esc(ex.restSec === null ? '' : ex.restSec)}"
        placeholder="${db.settings.defaultRestSec}"></label>
    <label class="field-row"><span>Increase step (kg)</span>
      <input class="field" inputmode="decimal" data-bind="ex" data-id="${ex.id}" data-field="increment" value="${esc(ex.increment === null ? '' : ex.increment)}"
        placeholder="${db.settings.defaultIncrement}"></label>
    <p class="hint">Leave blank to use the defaults from Settings.</p>
  </div>`;
}

/* ---------- exercise picker ---------- */

function screenPick(context, tplId) {
  const back = context === 'template' ? 'template/' + tplId : 'session';
  let html = `<header class="top">
    <button class="back" data-act="go" data-to="${back}">‹ Back</button>
    <h1>Add exercise</h1>
  </header><div class="pad">
    <div class="newex">
      <input class="field wide-field" id="newex" placeholder="New exercise name" enterkeyhint="done">
      <button class="ghost" data-act="create-ex" data-ctx="${context}" data-id="${tplId || ''}">Create</button>
    </div>
    <h2>Existing</h2><ul class="list">`;

  Object.values(db.exercises).forEach((e) => {
    html += `<li><button class="row" data-act="pick-ex" data-ctx="${context}" data-id="${tplId || ''}" data-ex="${e.id}">
      <span class="row-main">${esc(e.name)}</span>
      <span class="row-sub">rest ${restSecFor(e.id)}s${e.notes ? ' · ' + esc(e.notes) : ''}</span>
      <span class="chev">+</span>
    </button></li>`;
  });

  return html + '</ul></div>';
}

/* ---------- actions ---------- */

const actions = {
  go: (el) => nav('#/' + el.dataset.to),

  start: (el) => { startSession(el.dataset.id); nav('#/session'); },

  resume: () => nav('#/session'),

  finish: () => {
    const s = activeSession();
    const done = s ? s.entries.reduce((n, e) => n + e.sets.filter((x) => x.done).length, 0) : 0;
    if (done === 0) {
      if (!confirm('No sets ticked off. Finish anyway?')) return;
    }
    finishSession();
    cancelTimer();
    nav('#/home');
  },

  discard: () => {
    if (!confirm('Discard this session? Everything logged today is deleted.')) return;
    discardSession();
    cancelTimer();
    nav('#/home');
  },

  tick: (el) => {
    const s = activeSession();
    if (!s) return;
    const entry = s.entries[+el.dataset.ei];
    const set = entry.sets[+el.dataset.si];
    set.done = !set.done;
    if (set.done) {
      startTimer(entry.exerciseId, restSecFor(entry.exerciseId), entry.name);
    }
    saveNow();
    render();
  },

  'add-set': (el) => {
    const s = activeSession();
    const entry = s.entries[+el.dataset.ei];
    const prev = entry.sets[entry.sets.length - 1];
    entry.sets.push({ weight: prev ? prev.weight : '', reps: prev ? prev.reps : String(entry.target ?? ''), done: false });
    saveNow();
    render();
  },

  'del-set': (el) => {
    const s = activeSession();
    const entry = s.entries[+el.dataset.ei];
    if (entry.sets.length <= 1) return;
    entry.sets.pop();
    saveNow();
    render();
  },

  'rest-now': (el) => {
    const s = activeSession();
    const entry = s.entries[+el.dataset.ei];
    startTimer(entry.exerciseId, restSecFor(entry.exerciseId), entry.name);
  },

  'drop-ex': (el) => {
    const s = activeSession();
    const entry = s.entries[+el.dataset.ei];
    if (!confirm('Remove ' + entry.name + ' from today?')) return;
    s.entries.splice(+el.dataset.ei, 1);
    saveNow();
    render();
  },

  'ignore-suggest': (el) => {
    const s = activeSession();
    const entry = s.entries[+el.dataset.ei];
    const sug = suggestionFor(entry.exerciseId, s.id);
    entry.suggested = false;
    entry.sets.forEach((set) => {
      if (!set.done) set.weight = sug.lastWeight === null ? '' : String(sug.lastWeight);
    });
    saveNow();
    render();
  },

  'del-session': (el) => {
    if (!confirm('Delete this session permanently?')) return;
    deleteSession(el.dataset.id);
    nav('#/history');
  },

  'new-template': () => {
    const name = prompt('Name for the new workout');
    if (!name) return;
    const t = { id: uid('tpl'), name: name.trim(), items: [] };
    db.templates[t.id] = t;
    saveNow();
    nav('#/template/' + t.id);
  },

  'del-template': (el) => {
    if (!confirm('Delete this workout template? Past sessions are kept.')) return;
    delete db.templates[el.dataset.id];
    saveNow();
    nav('#/settings');
  },

  'move-up': (el) => moveItem(el.dataset.id, +el.dataset.i, -1),
  'move-down': (el) => moveItem(el.dataset.id, +el.dataset.i, 1),

  'tpl-remove': (el) => {
    const t = db.templates[el.dataset.id];
    t.items.splice(+el.dataset.i, 1);
    saveNow();
    render();
  },

  'pick-ex': (el) => addExercise(el.dataset.ctx, el.dataset.id, el.dataset.ex),

  'create-ex': (el) => {
    const input = document.getElementById('newex');
    const name = input && input.value.trim();
    if (!name) { if (input) input.focus(); return; }
    const ex = { id: uid('ex'), name, notes: '', restSec: null, increment: null };
    db.exercises[ex.id] = ex;
    saveNow();
    addExercise(el.dataset.ctx, el.dataset.id, ex.id);
  },

  'ask-notify': () => {
    if (!('Notification' in window)) return;
    Notification.requestPermission().then(() => render());
  },

  export: () => {
    const blob = new Blob([exportJSON()], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    const d = new Date();
    const stamp = d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
    a.href = url;
    a.download = `gymlogger-${stamp}.json`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  },

  'timer-cancel': () => cancelTimer(),
  'timer-add': () => addTime(30),
};

function moveItem(tplId, i, delta) {
  const t = db.templates[tplId];
  const j = i + delta;
  if (j < 0 || j >= t.items.length) return;
  const [item] = t.items.splice(i, 1);
  t.items.splice(j, 0, item);
  saveNow();
  render();
}

function addExercise(ctx, tplId, exId) {
  if (ctx === 'template') {
    const t = db.templates[tplId];
    if (!t) return;
    t.items.push({ exerciseId: exId, sets: 3, target: 12 });
    saveNow();
    nav('#/template/' + tplId);
  } else {
    const s = activeSession();
    if (!s) { nav('#/home'); return; }
    s.entries.push(buildEntry(exId, 3, 12));
    saveNow();
    nav('#/session');
  }
}

/* ---------- input binding ---------- */

function onInput(e) {
  const el = e.target;
  const bind = el.dataset.bind;
  if (!bind) return;

  if (bind === 'set') {
    const s = activeSession();
    if (!s) return;
    s.entries[+el.dataset.ei].sets[+el.dataset.si][el.dataset.field] = el.value;
    save();
  } else if (bind === 'hist') {
    const s = db.sessions[+el.dataset.sid];
    if (!s) return;
    s.entries[+el.dataset.ei].sets[+el.dataset.si][el.dataset.field] = el.value;
    save();
  } else if (bind === 'note') {
    const s = activeSession();
    if (!s) return;
    const entry = s.entries[+el.dataset.ei];
    entry.note = el.value;
    // The note lives on the exercise so it follows you into every future
    // session, and is snapshotted onto the entry for the historical record.
    const ex = exercise(entry.exerciseId);
    if (ex) ex.notes = el.value;
    save();
  } else if (bind === 'ex') {
    const ex = exercise(el.dataset.id);
    if (!ex) return;
    const f = el.dataset.field;
    if (f === 'restSec' || f === 'increment') {
      ex[f] = toNum(el.value);
    } else {
      ex[f] = el.value;
    }
    save();
  } else if (bind === 'tpl-name') {
    db.templates[el.dataset.id].name = el.value;
    save();
  } else if (bind === 'tpl-item') {
    const item = db.templates[el.dataset.id].items[+el.dataset.i];
    const n = toNum(el.value);
    item[el.dataset.field] = n === null ? '' : n;
    save();
  } else if (bind === 'setting') {
    const n = toNum(el.value);
    if (n !== null && n > 0) { db.settings[el.dataset.key] = n; save(); }
  }
}

/* ---------- wiring ---------- */

document.addEventListener('click', (e) => {
  const el = e.target.closest('[data-act]');
  if (!el) return;
  const fn = actions[el.dataset.act];
  if (!fn) return;
  e.preventDefault();
  primeAudio();
  fn(el);
});

document.addEventListener('input', onInput);

// Select-all on focus: fields come prefilled with the suggestion, so typing
// should replace it rather than append to it.
document.addEventListener('focusin', (e) => {
  if (e.target.classList && e.target.classList.contains('field')) {
    setTimeout(() => { try { e.target.select(); } catch (err) { /* ignore */ } }, 0);
  }
});

window.addEventListener('hashchange', render);
window.addEventListener('beforeunload', saveNow);
document.addEventListener('visibilitychange', () => { if (document.hidden) saveNow(); });

// Keep the session clock honest without re-rendering the whole screen.
setInterval(() => {
  const el = document.getElementById('elapsed');
  const s = activeSession();
  if (el && s) el.textContent = fmtDuration(Date.now() - s.startedAt);
}, 10000);

initTimer();
if (!location.hash) location.hash = '#/home';
render();

if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(() => { /* offline support unavailable */ });
  });
}
