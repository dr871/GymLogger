# GymLogger

A workout tracker with one job: show you what you lifted last time, right where
you enter what you're lifting now.

Single-page PWA. No backend, no accounts, no network. Everything lives in
`localStorage` on your phone.

## Running it

It's static files — no build step, no dependencies.

```sh
python3 -m http.server 8000
# then open http://localhost:8000
```

For the phone: serve it over HTTPS anywhere static (GitHub Pages works), open it
in the browser, and use **Add to Home Screen**. After the first load it works
with no network at all.

Service workers require HTTPS or `localhost` — over plain HTTP on a LAN IP the
app still runs, but it won't install or cache.

## What's pre-loaded

**Full Body** — leg press (3×12, 120s rest), chest press, lat pulldown, seated
cable row, leg curl (3×12, 90s rest), plank (3×40).

All of it is editable: rename anything, change sets and reps, reorder with the
up/down buttons, add or remove exercises, create more workout templates.

## How it works

**Last session's numbers** sit greyed out beside today's empty fields, matched
set for set. The lookup is per-exercise, not per-session — it finds the most
recent finished session that actually logged *that movement*, so skipping a
machine or running a different template doesn't break the target.

**Today's fields come prefilled.** Weight is last session's, or last + 2.5 kg if
you ticked every set at the target reps last time; reps are prefilled to the
target. Tapping a field selects it so typing replaces it. When a bump is
suggested there's a *Keep 85* button to ignore it and hold the weight.

**Notes** live on the exercise, so "seat 4, handles 2" follows you into every
future session. Each session also stores a snapshot, so old records keep what
was true at the time.

**The rest timer stores an absolute end time**, not a countdown. It's computed
from the wall clock on every tick, so locking the phone, switching apps or
force-quitting mid-rest doesn't matter — come back and it shows the truth, or
"Rest done". It vibrates and beeps on finish; enable notifications in Settings
to get an alert when the app isn't in front. Length is per-exercise and takes
effect immediately, even mid-session.

**Progress** plots the heaviest working set per session for one exercise. For
bodyweight work with no weight logged (the plank), it plots reps instead.

**Export** in Settings writes the whole store — exercises, templates, every
session — to a JSON file. Worth doing now and then: clearing your browser's site
data erases everything, and there's no server holding a copy.

## Layout

| File | |
|---|---|
| `index.html` | app shell, tab bar, rest-timer bar |
| `styles.css` | dark theme, 52px minimum tap targets |
| `js/store.js` | data model, persistence, last-session and suggestion logic |
| `js/app.js` | hash router, screens, event delegation |
| `js/timer.js` | wall-clock rest timer |
| `js/chart.js` | SVG line chart, no library |
| `sw.js` | cache-first service worker |

### Data model

One JSON blob under `gymlogger.v1`:

- `exercises` — the durable identity of a movement: name, note, rest, increment
- `templates` — an ordered list of `{exerciseId, sets, target}`
- `sessions` — what actually happened, with the exercise name and note
  snapshotted so later renames don't rewrite history
- `settings`, `timer`, `activeSessionId`

## Tests

```sh
npm install playwright && npx playwright install chromium
node test/e2e.mjs
```

34 end-to-end checks through a mobile-sized Chromium: the two-session flow,
suggestion and ignore, note persistence, timer behaviour across reloads, offline
operation, export, and that nothing tappable is under 44px.
