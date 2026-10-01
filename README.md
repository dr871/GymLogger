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

**A file from a newer build is never quietly downgraded.** Decoding drops what
it doesn't recognise, so restoring a newer backup would strip fields while
keeping the higher version number — the file would then claim to be something
it no longer is. Restore refuses it and says so. If the *live* file turns out
to be newer (easy to hit when a free-account build is reinstalled weekly), the
app still opens, but keeps the original verbatim as `data.v<N>.json` first, so
the next save can't write the loss back over it.

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

**Every exercise has a rep range** (e.g. 8–12; seconds for timed work) — a
target to aim at, not a rule the app enforces.

**The app never proposes a weight.** Today's fields open prefilled with last
session, set for set, and you change what you want to change. Gym stacks move
in pin positions plus small add-on tabs, so any number computed from a fixed
increment is as likely to be unloadable as not — better to show what you did
and let you type what you're doing.

**It does say when the range is used up.** Double progression means the reps
climb through the range, then the weight moves and the reps start again at the
bottom. When every working set of the last session reached the top of the range
*at one weight*, the exercise carries a cue — "Topped the range last time — add
weight" — naming no number. It is deliberately quiet: a ramp up to a single
heavy set, or a lighter back-off set carrying the high reps, is not evidence the
working weight is ready to move, so neither earns the cue. Assisted work is told
to take less help; bodyweight and timed work, which have no weight to add, are
told to raise the range.

**How an exercise is measured** decides what a set records:

| Measure | A set needs |
|---|---|
| Weight | weight > 0, reps > 0 |
| Assisted | assistance ≥ 0 (0 = unassisted), reps > 0 |
| Bodyweight | reps > 0 |
| Time | seconds > 0 |

Assisted work treats the *lowest* assistance as the best set. Assisted and
timed exercises hide or relabel the boxes to suit.

**A set can only be ticked once it's logged** according to its measure (table
above). Unticking is always allowed.

**Warm-up sets** — tapping a set's number toggles it. They're logged but never
count: not for records, volume, prefill, or whether a session "did" the
exercise, and last session's numbers line up against working sets only.

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

**Progress** leads with a sentence rather than a shape: what you last did
("70 kg × 12") and how it compares ("Best yet", "Up 5 kg on last time", "Same
weight, 2 more reps"). The comparison is in the weight you actually loaded, not
the estimate, because "up 6.67 kg" is nobody's idea of progress. Only exercises
you've logged are listed, most recently trained first; the weekly volume card
sits below the lift and draws only the weeks you have.

**The chart plots one of four metrics**, switchable above it: est. 1RM
(the default), heaviest set, reps, or volume. A weight-only line can sit flat
for months while the reps underneath it climb, and the estimate extrapolates
hard once a set passes about twelve reps — so neither is the whole story on its
own. Where the number comes from a single set, the point is labelled with that
set ("59×12") rather than the derived figure.

Under that it plots, per session, the best **estimated one-rep max** for
weighted work (Epley, `weight × (1 + reps/30)`) — so the line moves while reps
climb at one weight, not only when the weight changes — and otherwise the best
set in the exercise's own unit: seconds, reps, or for assisted work the
assistance, labelled *lower is better*.

**Personal records** are derived from history, never stored, so they can't go
stale: heaviest set and best estimated 1RM (Epley) for weighted work, least
assistance, most reps, longest hold. All of them show under the Progress chart.

What gets *announced* is narrower, so the one line that matters isn't buried:
finishing a session reports **at most one record per exercise** — the heaviest
set where there is one, otherwise the estimate, which is what catches more reps
at the same weight — and says nothing at all for an exercise's first session,
since a baseline isn't a record. Ties at the same weight keep the better set.

**Share this workout** (on any session in History) puts a plain-text summary on
the share sheet, for sending to whoever asks what you did:

```
Full Body — Thu, 24 Sep
48 min · 18 sets

Leg press — 70 kg × 10, 11, 12
Plank — 45s, 45s, 45s

Best yet: Leg press 70 kg × 12
```

Warm-ups, un-ticked sets and exercises you didn't log are left out.

**Weekly volume** is working sets per muscle group per week — the unit the
10–20 sets/muscle guideline uses, and a fair comparison across a leg press and
a lateral raise where tonnage isn't. Each exercise has a muscle group (from the
catalogue, editable, read live so recategorising moves its history). Home shows
this week against last; Progress charts the last eight weeks stacked by muscle.
For a full-body routine this is the quickest way to see whether the template
is balanced.

**Export** shares the whole store as a JSON file through the standard share
sheet.

**Diagnostics.** The app recovers from a damaged or unreadable data file on its
own — setting the original aside, falling back to the Files-app mirror, or
starting from the seed. That is right, but it is also silent, so every one of
those recoveries is written to a small log, along with the things you do that
can't be undone: launches, sessions started, finished, discarded and deleted,
exercises deleted, backups exported and restored. Recording deletions is the
point of the routine half — it is what tells a session you removed apart from a
session that disappeared.

Retention is by age, not by count. Routine events are kept for **7 days**, which
covers the refresh cycle a sideloaded build lives on. Problems — warnings and
errors — are kept for **30 days**, because they are rare, cost nothing to hold,
and a corruption noticed a fortnight later is exactly the case a 7-day window
would throw away. A hard cap of 500 events is the backstop against something
failing in a loop. In practice an event is about 140 bytes, so a heavy week is a
few KB.

Settings › Diagnostics exports it as plain text, alongside the build number, how
much is stored, and the files on disk. The log lives in its own file beside the
data rather than inside it: the events most worth reading are about the data file
being unreadable, and a log stored in that file would be lost exactly when it was
wanted. It carries counts only — no exercise names, no weights — so it can be
sent to someone.

**Settings › About** shows the version and build, matching what `build-ipa.sh`
stamped, so a report names a build exactly.

## Layout

| Path | |
|---|---|
| `ios/GymLogger/Core/Models.swift` | value types for the whole data model |
| `ios/GymLogger/Core/Logic.swift` | last-session lookup, prefill, progress series |
| `ios/GymLogger/Core/Diagnostics.swift` | the event log and the plain-text report |
| `ios/GymLogger/Core/Decoding.swift` | forgiving decode — see below |
| `ios/GymLogger/Core/Presets.swift` | exercise catalogue and standard workouts |
| `ios/GymLogger/Core/Records.swift` | personal records and weekly volume, derived from history |
| `ios/GymLogger/Core/DataFile.swift` | reading and writing the one file, and recovering from a damaged one |
| `ios/GymLogger/Store.swift` | persistence, notifications, SwiftUI plumbing |
| `ios/GymLogger/Views/` | one file per screen, plus `Theme` and `Components` |
| `ios/Tests/CoreTests/` | 188 unit tests over the logic layer |
| `ios/UITests/` | 6 screen tests driving the real UI |
| `ios/build-ipa.sh` | unsigned `.ipa` for sideloading |

`Core/` is deliberately plain Foundation — no SwiftUI, no Combine — so the part
that decides what number to show you builds and tests anywhere, including on
Linux CI.

### Data

One JSON file in Application Support:

- `exercises` — the durable identity of a movement: name, note, rest,
  `measure` (`weight` · `assisted` · `bodyweight` · `time`) and
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

217 tests over the logic layer: the progression cue for each measure and the
cases that must not trigger it, every prefill across the four measures, warm-up
sets never counting, set-completion rules,
rep ranges, estimated-max progress, personal records and when one counts as
new, weekly sets per muscle, which workout is next, duplicating and adding to
workouts, per-exercise history lookup, note propagation, the diagnostic log
(both retention windows, the hard cap, persistence across a restart, that a
clean file read records nothing, and that the report leaks no exercise names),
the
wall-clock timer, decode robustness (including files from before measures,
ranges, muscles and warm-ups existed), exercise deletion, backup restore, and
the exercise catalogue and presets. No Xcode needed — it runs on the command line.

Six **screen tests** drive the real UI through the flows that matter, in
`ios/UITests/`:

```sh
cd ios && xcodebuild test -project GymLogger.xcodeproj -scheme GymLogger \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

They cover logging a set (a set can't be ticked until it's logged, and can once
it is), finishing a session and finding it in History, sharing it, removing an
exercise from a workout, adding one from the catalogue, and Export offering the
backup file. The last three are regression tests for bugs found on a phone.
Each launches with `--uitest-reset`, so it starts from the seeded workout in a
throwaway file and never touches real data.

That leaves the rest of the SwiftUI layer without automated coverage. It builds
clean with Xcode 26, is exercised by hand on an iPhone 17 Pro simulator
(iOS 26.5), and runs on a physical iPhone on iOS 27, sideloaded with SideStore.

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
