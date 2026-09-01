# GymLogger

A workout tracker with one job: show you what you lifted last time, right where
you enter what you're lifting now.

Native iOS app, SwiftUI, iPhone. No backend, no accounts, no login — everything
lives on the phone.

## Building it

Needs a Mac with **Xcode 26** (deploying to an iOS 26 device requires a matching
Xcode). Deployment target is iOS 26.

```sh
open ios/GymLogger.xcodeproj
```

1. Select the **GymLogger** target → **Signing & Capabilities**.
2. Set **Team** to your Apple ID — add one under Xcode → Settings → Accounts.
   A free Apple ID is enough; no paid developer account needed.
3. Change the bundle identifier from `com.example.GymLogger` to something
   unique, e.g. `com.yourname.GymLogger`. Free accounts reject identifiers
   someone else has already registered.
4. Plug in your iPhone, choose it as the run destination, press **⌘R**.
5. First run only: on the phone, **Settings → General → VPN & Device
   Management** → trust your developer certificate.
6. The first time you tick off a set, iOS asks to allow notifications. Accept,
   or the rest timer can only buzz while the app is in front. It's re-offered
   under Settings in the app.

### The 7-day cycle

Free-account builds stop launching after 7 days. Plug in, press ⌘R, and it
renews — the app is replaced in place and **your training history survives**.

What does *not* survive is deleting the app: that removes its data container and
everything in it. There is no server holding a copy. So use **Settings → Export
all data** now and then and put the JSON somewhere safe — iCloud Drive, a mail
to yourself, anywhere off the phone.

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

**The rest timer schedules a local notification with the system**, so it reaches
you with the app backgrounded, the phone locked, or killed outright. (Local
notifications need no special entitlement, so this works on a free account.) The
countdown itself is stored as an absolute end time and rendered from the wall
clock, so it can't drift or stall. Length is per-exercise and takes effect
immediately, even mid-session.

**Progress** plots the heaviest working set per session for one exercise. For
bodyweight work with no weight logged (the plank), it plots reps instead.

**Export** shares the whole store as a JSON file through the standard share
sheet.

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

`ios/project.yml` regenerates an equivalent Xcode project via
`brew install xcodegen && xcodegen generate` if the checked-in one ever goes
stale.
