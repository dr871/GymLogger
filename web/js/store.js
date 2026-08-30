// Data layer: one JSON blob in localStorage. Small enough to read/write whole.

const KEY = 'gymlogger.v1';

export const uid = (p) => p + '_' + Math.random().toString(36).slice(2, 9) + Date.now().toString(36).slice(-3);

function seedData() {
  const mk = (name, opts = {}) => ({
    id: uid('ex'),
    name,
    notes: '',
    restSec: null,      // null = fall back to settings.defaultRestSec
    increment: null,    // null = fall back to settings.defaultIncrement
    ...opts,
  });

  const legPress = mk('Leg press', { restSec: 120 });
  const chestPress = mk('Chest press');
  const latPulldown = mk('Lat pulldown');
  const cableRow = mk('Seated cable row');
  const legCurl = mk('Leg curl');
  const plank = mk('Plank');

  const list = [legPress, chestPress, latPulldown, cableRow, legCurl, plank];
  const exercises = {};
  list.forEach((e) => { exercises[e.id] = e; });

  const tpl = {
    id: uid('tpl'),
    name: 'Full Body',
    items: [
      { exerciseId: legPress.id, sets: 3, target: 12 },
      { exerciseId: chestPress.id, sets: 3, target: 12 },
      { exerciseId: latPulldown.id, sets: 3, target: 12 },
      { exerciseId: cableRow.id, sets: 3, target: 12 },
      { exerciseId: legCurl.id, sets: 3, target: 12 },
      { exerciseId: plank.id, sets: 3, target: 40 },
    ],
  };

  return {
    version: 1,
    settings: { defaultRestSec: 90, defaultIncrement: 2.5 },
    exercises,
    templates: { [tpl.id]: tpl },
    sessions: [],
    activeSessionId: null,
    timer: null,
  };
}

function load() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return seedData();
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || !parsed.exercises) return seedData();
    // Fill in anything a older/partial blob is missing rather than throwing it away.
    return {
      version: 1,
      settings: { defaultRestSec: 90, defaultIncrement: 2.5, ...(parsed.settings || {}) },
      exercises: parsed.exercises || {},
      templates: parsed.templates || {},
      sessions: Array.isArray(parsed.sessions) ? parsed.sessions : [],
      activeSessionId: parsed.activeSessionId || null,
      timer: parsed.timer || null,
    };
  } catch (err) {
    console.error('Could not read saved data, starting fresh', err);
    return seedData();
  }
}

export const db = load();

let pending = null;
export function save() {
  // Coalesce bursts of keystrokes into one write.
  if (pending) clearTimeout(pending);
  pending = setTimeout(saveNow, 120);
}

export function saveNow() {
  if (pending) { clearTimeout(pending); pending = null; }
  try {
    localStorage.setItem(KEY, JSON.stringify(db));
  } catch (err) {
    console.error('Save failed', err);
    alert('Could not save — device storage may be full.');
  }
}

/* ---------- lookups ---------- */

export function exercise(id) {
  return db.exercises[id];
}

export function restSecFor(exId) {
  const ex = exercise(exId);
  return (ex && ex.restSec) || db.settings.defaultRestSec;
}

export function incrementFor(exId) {
  const ex = exercise(exId);
  return (ex && ex.increment) || db.settings.defaultIncrement;
}

export function activeSession() {
  if (!db.activeSessionId) return null;
  return db.sessions.find((s) => s.id === db.activeSessionId) || null;
}

export function finishedSessions() {
  return db.sessions.filter((s) => s.finishedAt).sort((a, b) => b.startedAt - a.startedAt);
}

function entryHasWork(entry) {
  return entry.sets.some((s) => s.done);
}

// Most recent *finished* session that actually logged this exercise.
// Per-exercise rather than per-session, so it still works if you skip a
// movement or run a different template.
export function lastEntryFor(exId, excludeSessionId) {
  const list = finishedSessions();
  for (const s of list) {
    if (s.id === excludeSessionId) continue;
    const e = s.entries.find((x) => x.exerciseId === exId && entryHasWork(x));
    if (e) return { entry: e, session: s };
  }
  return null;
}

export function toNum(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = parseFloat(String(v).replace(',', '.'));
  return Number.isFinite(n) ? n : null;
}

// A bump is earned when every set was ticked off, hit the target, and carried
// a weight. No weight logged (bodyweight work) means there is nothing to bump.
export function suggestionFor(exId, excludeSessionId) {
  const last = lastEntryFor(exId, excludeSessionId);
  if (!last) return { weight: null, earned: false, last: null };

  const sets = last.entry.sets.filter((s) => s.done);
  const weights = sets.map((s) => toNum(s.weight)).filter((w) => w !== null);
  const topWeight = weights.length ? Math.max(...weights) : null;

  const target = toNum(last.entry.target);
  const allHit =
    sets.length > 0 &&
    sets.length >= (last.entry.sets.length || 0) &&
    target !== null &&
    sets.every((s) => {
      const r = toNum(s.reps);
      return r !== null && r >= target;
    });

  const earned = allHit && topWeight !== null;
  const inc = incrementFor(exId);
  return {
    weight: earned ? Math.round((topWeight + inc) * 100) / 100 : topWeight,
    lastWeight: topWeight,
    earned,
    last,
  };
}

/* ---------- mutations ---------- */

export function startSession(templateId) {
  const tpl = db.templates[templateId];
  if (!tpl) return null;

  const session = {
    id: uid('s'),
    templateId,
    name: tpl.name,
    startedAt: Date.now(),
    finishedAt: null,
    entries: tpl.items.map((item) => buildEntry(item.exerciseId, item.sets, item.target)),
  };

  db.sessions.push(session);
  db.activeSessionId = session.id;
  saveNow();
  return session;
}

export function buildEntry(exId, setCount, target) {
  const ex = exercise(exId);
  const sug = suggestionFor(exId);
  const sets = [];
  for (let i = 0; i < setCount; i++) {
    sets.push({
      // Prefilled with the suggestion so a repeat session needs zero typing.
      weight: sug.weight === null ? '' : String(sug.weight),
      reps: target === null || target === undefined ? '' : String(target),
      done: false,
    });
  }
  return {
    exerciseId: exId,
    name: ex ? ex.name : 'Exercise',
    target,
    restSec: restSecFor(exId),
    note: ex ? ex.notes : '',
    sets,
    suggested: sug.earned,
  };
}

export function finishSession() {
  const s = activeSession();
  if (!s) return;
  s.finishedAt = Date.now();
  db.activeSessionId = null;
  db.timer = null;
  saveNow();
}

export function discardSession() {
  const s = activeSession();
  if (!s) return;
  db.sessions = db.sessions.filter((x) => x.id !== s.id);
  db.activeSessionId = null;
  db.timer = null;
  saveNow();
}

export function deleteSession(id) {
  db.sessions = db.sessions.filter((x) => x.id !== id);
  if (db.activeSessionId === id) db.activeSessionId = null;
  saveNow();
}

export function exportJSON() {
  return JSON.stringify(db, null, 2);
}
