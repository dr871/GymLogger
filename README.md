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
3. The bundle identifier is `com.hellorogers.gymlogger`. If you're building
   under a different Apple ID, change it to your own reverse-DNS name first —
   free accounts reject identifiers someone else has already registered — and
   do it *before* the first install: iOS treats a new identifier as a
   different app, so history under the old one is left behind.
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
everything in it. There is no server holding a copy. Two things cover that:

- **Settings → Export all data** hands the JSON to the share sheet. Put it
  anywhere off the phone. Home nudges you when it's been a fortnight.
- **Settings → Restore from backup** loads one back, showing what's in the file
  and what it will replace before anything changes.

A copy of the live data is also kept current in the **Files** app, under On My
iPhone → GymLogger → `GymLogger-backup.json`, so you can copy it out without
opening the app. Deleting that copy is harmless; the live file is elsewhere.

## Sideloading (no Mac at install time)

```sh
ios/build-ipa.sh            # → ios/build/GymLogger.ipa
```

Builds an **unsigned** Release `.ipa` — no Apple ID, certificate or profile
involved. Hand it to a signing service, AltStore or SideStore, which signs it
and installs it. The app needs no entitlements (local notifications don't
require one), so any signing route works.

The build number is the git commit count, so the version shown under
**Settings → General → About → GymLogger** — or in your signing tool — tells you
exactly which build is on the phone.

**Updating:** build a new `.ipa`, sign it, and install it **over the top**.
Never delete the app first — that erases the data container, including the
Files-app backup copy inside it. Export first if in any doubt.

**If the certificate expires or is revoked**, the app stops opening but its data
stays where it is. Re-sign and install over the top, and everything's back.

## What's pre-loaded

**Full Body** — leg press (3×12, 120s rest), chest press, lat pulldown, seated
cable row, leg curl (3×12, 90s rest), plank (3 × 30–60s).

All of it is editable: rename anything, change sets and reps, reorder with the
up/down buttons, add or remove exercises, delete an exercise from the library
outright, create more workout templates.

**Workouts** is reachable from Home as well as Settings. *+ Add exercise*
browses a catalogue of ~30 standard exercises grouped by muscle, alongside your
own; the search box also creates a custom one when nothing matches. *+ New
workout* offers standard splits — Push, Pull, Legs, Upper, Lower, Full body —
as a ticklist, so you take only the exercises you want. Nothing is duplicated:
an exercise already in your library is reused by name.

## How it works

**Home leads with the workout that's waited longest** — never done first,
then least recently finished — and says why ("last done Sat, 5 Sep · up
next"). With one workout, nothing changes.

**Last session's numbers** sit greyed out beside today's fields, matched set for
set. The lookup is per-exercise, not per-session — it finds the most recent
finished session that actually logged *that movement*, so skipping a machine or
running a different template doesn't break the target.

**Every exercise has a rep range** (e.g. 8–12; seconds for timed work) and
**progression is double progression**: climb the range at one weight, and once
every set hits the top, the weight moves and reps drop back to the bottom.
Today's fields come prefilled accordingly — last session's numbers set for set
while you're climbing, or the bump when it's earned, with a *Keep 80 kg* button
to hold. A fixed target is just a range with equal ends, and no range means no
bump is ever suggested.

**How an exercise is measured** decides what a set records and what moves:

| Measure | A set needs | When every set hits the top of the range |
|---|---|---|
| Weight | weight > 0, reps > 0 | weight + increment, reps back to the bottom |
| Assisted | assistance ≥ 0 (0 = unassisted), reps > 0 | assistance − increment, down to 0 |
| Bodyweight | reps > 0 | +1 rep, up to the top of the range |
| Time | seconds > 0 | +5s, up to the top of the range |

For bodyweight and timed work there is no weight to move, so "hitting the top"
means every set matched your best; the reps themselves climb until the range is
full. Assisted and timed exercises hide or relabel the boxes to suit.

**A set can only be ticked once it's logged** according to its measure (table
above). Unticking is always allowed.

**Warm-up sets** — *+ Warm-up* adds one at the top at roughly half the
working weight; tapping a set's number toggles it. They're logged but never
count: not for progression, records, volume, or whether a session "did" the
exercise, and last session's numbers line up against working sets only.

**±** chips step every un-ticked set by the exercise's increment, so a stack
that doesn't match the suggestion is two taps rather than a decimal pad.

**Timed holds have a timer**: ▶ counts up in place of the seconds field, ■
writes the time. It buzzes as you pass the target.

**Adding an exercise to today** offers to add it to the workout too, so a
one-off stays one-off and a keeper is kept. **Duplicate this workout** in the
editor makes a B day out of an A day.

**Notes** live on the exercise, so "seat 4, handles 2" follows you into every
future session. Each session also stores a snapshot, so old records keep what
was true at the time — renaming an exercise doesn't rewrite history.

**The rest timer schedules a local notification with the system**, so it reaches
you with the app backgrounded, the phone locked, or killed outright. (Local
notifications need no special entitlement, so this works on a free account.) The
countdown itself is stored as an absolute end time and rendered from the wall
clock, so it can't drift or stall. Length is per-exercise and takes effect
immediately, even mid-session.

**Text follows the phone's text-size setting** (Settings › Display & Brightness
› Text Size, and the accessibility sizes). Rows of fields — a set's weight and
reps, a workout's sets and rep range, the reorder buttons — stack vertically at
the accessibility sizes rather than squeezing to "…".

**During a session the screen stays awake**, so a phone on the bench doesn't
need unlocking between sets. Only while the session screen is showing.

**Progress** plots, per session, the best **estimated one-rep max** for
weighted work (Epley, `weight × (1 + reps/30)`) — so the line moves while reps
climb at one weight, not only when the weight changes — and otherwise the best
set in the exercise's own unit: seconds, reps, or for assisted work the
assistance, labelled *lower is better*.

**Personal records** are derived from history, never stored, so they can't go
stale: heaviest set and best estimated 1RM (Epley) for weighted work, least
assistance, most reps, longest hold. They show under the Progress chart, a
session's detail lists any it set, and finishing a session that beat one pops
a summary. A record counts when it strictly beats every earlier session — so
your first session sets the baseline.

**Weekly volume** is working sets per muscle group per week — the unit the
10–20 sets/muscle guideline uses, and a fair comparison across a leg press and
a lateral raise where tonnage isn't. Each exercise has a muscle group (from the
catalogue, editable, read live so recategorising moves its history). Home shows
this week against last; Progress charts the last eight weeks stacked by muscle.
For a full-body routine this is the quickest way to see whether the template
is balanced.

**Export** shares the whole store as a JSON file through the standard share
sheet.

## Layout

| Path | |
|---|---|
| `ios/GymLogger/Core/Models.swift` | value types for the whole data model |
| `ios/GymLogger/Core/Logic.swift` | last-session lookup, suggestion rule, progress series |
| `ios/GymLogger/Core/Decoding.swift` | forgiving decode — see below |
| `ios/GymLogger/Core/Presets.swift` | exercise catalogue and standard workouts |
| `ios/GymLogger/Core/Records.swift` | personal records and weekly volume, derived from history |
| `ios/GymLogger/Store.swift` | persistence, notifications, SwiftUI plumbing |
| `ios/GymLogger/Views/` | one file per screen, plus `Theme` and `Components` |
| `ios/Tests/CoreTests/` | 137 unit tests over the logic layer |
| `ios/build-ipa.sh` | unsigned `.ipa` for sideloading |

`Core/` is deliberately plain Foundation — no SwiftUI, no Combine — so the part
that decides what number to show you builds and tests anywhere, including on
Linux CI.

### Data

One JSON file in Application Support:

- `exercises` — the durable identity of a movement: name, note, rest,
  increment, `measure` (`weight` · `assisted` · `bodyweight` · `time`) and
  `muscle` (chest · back · shoulders · arms · legs · core, or none)
- `templates` — an ordered list of `{exerciseId, sets, targetMin, targetMax}`
- `sessions` — what actually happened, with name and note snapshotted; each
  set carries `warmup`
- `settings`, `timer`, `activeSessionId`

On launch the live file is tried first; if it's missing or unreadable, the
mirror in Documents is loaded instead and a fresh live file written, so a torn
write costs nothing while an intact copy sits next door. An unreadable live
file is kept as `data.corrupt.json`. `version` is 2 (measures, ranges, muscles,
warm-ups); version-1 files still load.

Swift's synthesized `Codable` throws when a key is missing rather than using the
property's default. For the single file holding all of someone's training
history that's the wrong trade, so `Decoding.swift` makes every non-essential
field fall back instead. If the file is unreadable outright, `Store` moves it to
`data.corrupt.json` rather than overwriting it.

## Tests

```sh
cd ios && swift test
```

137 tests over the logic layer: double progression for each measure and every
way it should *not* fire, warm-up sets never counting, set-completion rules,
rep ranges, estimated-max progress, personal records and when one counts as
new, weekly sets per muscle, which workout is next, duplicating and adding to
workouts, weight stepping, per-exercise history lookup, note propagation, the
wall-clock timer, decode robustness (including files from before measures,
ranges, muscles and warm-ups existed), exercise deletion, backup restore, and
the exercise catalogue and presets. No Xcode needed — it runs on the command line.

The SwiftUI layer has no automated coverage. It builds clean with Xcode 26, is
exercised by hand on an iPhone 17 Pro simulator (iOS 26.5), and now runs on a
physical iPhone on iOS 27, sideloaded with SideStore.

Running it on a phone is what found the first two view-layer bugs, both of them
in code that had been written but never actually run: removing an exercise from
a workout crashed on a stale row index, and Export opened an empty share sheet
because the sheet was built before the file's URL had landed. Neither was
reachable from the logic tests. If the UI misbehaves, reproduce it on the
simulator first — both bugs reproduced there every time once the exact tap was
known.

`ios/project.yml` regenerates an equivalent Xcode project via
`brew install xcodegen && xcodegen generate` if the checked-in one ever goes
stale.
