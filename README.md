# GymLogger

A workout tracker with one job: show you what you lifted last time, right where
you enter what you're lifting now.

Native iOS app. No backend, no accounts, no login — everything lives on the
phone.

- **`ios/`** — the app. SwiftUI, iPhone, iOS 16+. **This is the one to build.**
- **`web/`** — the original PWA prototype. Superseded, kept for reference.

## Building it

You need a Mac with Xcode 15 or newer.

```sh
open ios/GymLogger.xcodeproj
```

Then:

1. Select the **GymLogger** target → **Signing & Capabilities**.
2. Set **Team** to your Apple ID (add one under Xcode → Settings → Accounts).
   A free Apple ID is enough.
3. Change the bundle identifier from `com.example.GymLogger` to something
   unique — `com.yourname.GymLogger`. Free accounts reject identifiers that
   someone else already registered.
4. Plug in your iPhone, pick it as the run destination, and press ⌘R.
5. First run only: on the phone, **Settings → General → VPN & Device Management**
   → trust your developer certificate.

With a free Apple ID the app stops launching after 7 days and you re-run ⌘R to
renew it. A paid developer account ($99/yr) extends that to a year.

Grant the notification prompt when it appears, or the rest timer can only buzz
while the app is open. It's also re-offered under Settings in the app.

## What's pre-loaded

**Full Body** — leg press (3×12, 120s rest), chest press, lat pulldown, seated
cable row, leg curl (3×12, 90s rest), plank (3×40).

All of it is editable: rename anything, change sets and reps, reorder with the
up/down buttons, add or remove exercises, create more workout templates.

## How it works

**Last session's numbers** sit greyed out beside today's fields, matched set for
set. The lookup is per-exercise, not per-session — it finds the most recent
finished session that actually logged *that movement*, so skipping a machine or
running a different template doesn't break the target.

**Today's fields come prefilled.** Weight is last session's, or last + 2.5 kg if
you ticked every set at the target reps last time; reps are prefilled to the
target. When a bump is suggested there's a *Keep 85* button to ignore it and
hold the weight.

**Notes** live on the exercise, so "seat 4, handles 2" follows you into every
future session. Each session also stores a snapshot, so old records keep what
was true at the time — renaming an exercise doesn't rewrite history.

**The rest timer schedules a local notification with the system.** It reaches
you with the app backgrounded, the phone locked, or the app killed outright —
which is the main thing a native app buys over the web version, where iOS
freezes the page the moment you switch away. The countdown itself is stored as
an absolute end time and rendered from the wall clock, so it can't drift or
stall. Length is per-exercise and takes effect immediately, even mid-session.

**Progress** plots the heaviest working set per session for one exercise. For
bodyweight work with no weight logged (the plank), it plots reps instead.

**Export** in Settings shares the whole store — exercises, templates, every
session — as a JSON file, via the standard share sheet. Worth doing now and
then: the data lives only on this phone, and deleting the app erases it.

## Layout

| Path | |
|---|---|
| `ios/GymLogger/Core/Models.swift` | value types for the whole data model |
| `ios/GymLogger/Core/Logic.swift` | last-session lookup, suggestion rule, progress series |
| `ios/GymLogger/Core/Decoding.swift` | forgiving decode — see below |
| `ios/GymLogger/Store.swift` | persistence, notifications, SwiftUI plumbing |
| `ios/GymLogger/Views/` | one file per screen, plus `Theme` and `Components` |
| `ios/Tests/CoreTests/` | 30 unit tests over the logic layer |

`Core/` is deliberately plain Foundation — no SwiftUI, no Combine — so the part
that decides what number to show you builds and tests anywhere, including on
Linux CI.

### Data

One JSON file in Application Support:

- `exercises` — the durable identity of a movement: name, note, rest, increment
- `templates` — an ordered list of `{exerciseId, sets, target}`
- `sessions` — what actually happened, with name and note snapshotted
- `settings`, `timer`, `activeSessionId`

Swift's synthesized `Codable` throws when a key is missing rather than using the
property's default. For the single file holding all of someone's training
history that's the wrong trade, so `Decoding.swift` makes every non-essential
field fall back instead. If the file is unreadable outright, `Store` moves it to
`data.corrupt.json` rather than overwriting it.

## Tests

```sh
cd ios && swift test
```

30 tests over the logic layer: the suggestion rule and every way it should
*not* fire, per-exercise history lookup, note propagation, the wall-clock timer,
and decode robustness. No Xcode needed — it runs on the command line.

The SwiftUI layer has no automated coverage; it was written against the tested
core but has not been run on a device.

## The web prototype

`web/` holds the original PWA — a working, offline-capable version of the same
app with 34 end-to-end browser tests (`cd web && node test/e2e.mjs`). It is
superseded by the iOS app and isn't being kept in step with it.
