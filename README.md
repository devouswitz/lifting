# Lifting

Native SwiftUI workout tracker. iOS 17 or later. Offline by default, with optional backup and sync through a user-selected folder. No app accounts, subscriptions, external packages, or hosted backend.

## Run on iPhone

1. Install Xcode, then add an iOS simulator runtime or connect an iPhone.
2. Open `Lifting.xcodeproj`.
3. Select the Lifting target and your signing team under Signing & Capabilities. Change the bundle identifier if needed.
4. Choose the Lifting scheme and your device, then Run.

An App Store release and distribution signing are not configured.

## Mac preview

Open the included `Lifting Preview.app`, or build with:

```sh
./scripts/build-mac-preview.sh
```

The preview runs the same SwiftUI views and training engine. It does not replace testing on an iPhone.

For sample history without saving any changes:

```sh
open -n '../Lifting Preview.app' --args --demo
```

## Controls

- Train: load a Program and start its next Day. Each program remembers its place. Completing another day does not skip the next one.
- Programs: add blank days or copy day templates, then reorder, edit, duplicate, or export. Templates stay reusable; each copy has independent prescriptions and tracking.
- Prescription: configure working load, each set, percentage warm-ups, rep ranges, AMRAP, time, distance, RPE, rest, notes, and optional progression.
- Set targets: choose No count for RPE-only sets, Reps for a fixed target, or Rep range for minimum and maximum reps. Warm-ups can use a percentage of the working set.
- Workout: tap the checkbox to log a set, tap a value to edit, tap the working load to update remaining work and percentage warm-ups.
- Substitute: choose Today only or Future sessions, then an exercise. Completed sets stay on the original exercise. Future changes affect this day slot only.
- Drop: choose reductions, number of drops, and reps. Recurring drop loads stay relative to working weight.
- MYO: choose activation reps, mini-set count, mini-set reps, and rest. Replace remaining work sets if desired. Add mini-sets, change values, or remove sets during the workout.
- Drop/MYO targets use the same exact reps, rep ranges, no-count, RPE, time, and distance controls as ordinary sets. Percentage fields accept typed values and 5-point adjustments. Failure is also available as a set type.
- Superset / Circuit: link two or more exercises in a day editor or live workout. Choose transition and round rest. Logging advances the focused panel around the group; warm-ups and drop/MYO chains finish before moving on. Uneven set counts skip completed movements. Live links can be saved to the day.
- Warm-up presets: create named, ordered schemes in Settings, or save a prescription's current warm-ups. Apply a preset to selected day exercises or live exercises. Replace or append warm-ups, and optionally save live changes to the day variants. Completed warm-ups are retained. Presets copy their plans, so editing a preset does not rewrite existing days.
- Save to this day: makes live load, drop/MYO, warm-up, or link changes recur. Otherwise they apply to the current workout.
- Tap an exercise header to expand or collapse it. Opening one focuses that exercise. Warm-ups and working sets have separate compact tables. Automatic collapse after completion is optional in Settings. Workout options include Collapse All and Expand All.
- Each set's menu (tap the set number, or long-press the row) edits today's targets, logs reps, time, or distance, sets rest, changes type, or deletes the set. Range targets stay visible without assuming an exact rep count. Tap the range to optionally record reps completed. Uncounted reps do not contribute to rep totals, volume, estimated max, or automatic progression.
- History: browse dated results or a selectable monthly calendar with comparisons to the previous month. Rest days count only days that have passed. Open a workout to inspect or edit its sets and notes; swipe a set in Edit to delete it.
- Progress: choose a program or All programs, then compare separate exercise and day tracks, choose a metric and date range, or scrub a graph for actual recorded values. Exercise details include dated results.
- Progress > Muscles: compare logged sets or load volume by primary muscle, with optional half-set credit for secondary muscles. Program and date filters apply. Warm-ups and cardio are excluded; drop/MYO sets count individually. Unknown rep counts contribute no invented volume. Muscle assignments can be edited with an exercise; new sessions snapshot them.
- Settings: units and appearance, workout preferences, plate sizes, folder backup/sync, JSON backup/restore, and CSV import/export.

Weights are stored in kilograms and converted for display. Warm-up and drop percentages round down to the variant's increment. RPE is a user-entered target or observation.

## Data

Data is stored as an atomic, versioned JSON file in the app's Application Support directory. The previous valid save is kept as `training.json.previous`. Backup replacement preserves the pre-import state as `training.json.before-import`. Corrupt files are not silently replaced with starter data.

Completed sessions snapshot program and day names, prescriptions, notes, and values. History uses Program - Day titles. Day and program edits do not rewrite history. Exercise identity and variant identity are separate. Progression applies only to the relevant variant and requires all non-warm-up sets to be complete.

Deleting the app removes its on-device data. Export backups to a location you control.

## Sharing CSV

Export CSV from a day/template or program editor. Import CSV from Train, Programs, or Settings. Review the preview, then Add or Add and Load. Imports create independent copies and preserve existing data.

Day/program CSV carries ordered days and exercises, working loads, relative warm-up/drop formulas, MYO sets, targets, rest, notes, groups, and progression rules. A minimal hand-edited CSV needs `day,exercise` columns. Use an exported file as the full schema; weight columns ending `_kg` use kilograms, time uses seconds, and distance uses meters. UTF-8, quoted multiline fields, comma and semicolon separators are supported. Invalid files are rejected before changing data.

Logged-set CSV is a separate format for history, with actual values, rep-range targets, program identity, notes, times, linked groups, muscle snapshots, source fields, and stable IDs. Reimporting the same workouts skips duplicates. Legacy Lifting CSV is accepted with inferred exercise types and no duration. JSON backup is the complete device backup, including active workouts, settings, and warm-up presets.

## Importing other apps

Settings > Import workout data detects Strong, Hevy, and FitNotes CSV headers. Confirm unspecified units, date format, and column assignments, then review the workouts before adding them. Other CSVs can use the same column mapper. Flat set-record JSON and Hevy-style nested workout/exercise/set JSON are also supported. No login, API key, or server is required.

Imports preserve units, actual values, supported set types, notes, groups, available duration, and source fields. Familiar exercise names with equipment suffixes can map to the existing catalog; day-specific tracks remain separate. Reimporting an unchanged export skips its workouts. Optionally build a program from each latest logged day. These reconstructed days use exported results; the file cannot supply saved prescriptions or progression rules that the source app omitted. Ambiguous dates, invalid values, encrypted files, and proprietary database backups are rejected rather than guessed. GreySkull-specific binary/cloud backup formats have not been validated.

## Optional folder backup and sync

In Settings, choose the same iCloud Drive folder on each device. Automatic backup and Device sync are separate switches, both off initially. A local folder works for backup; cross-device transport requires iCloud Drive or another folder provider. This approach needs no CloudKit container or backend subscription. iCloud includes 5 GB free, shared with the user's other iCloud data; extra storage is not free.

The app checks the folder while open, after changes, and on foreground activation. OS/provider upload and download timing is outside the app's control. Routines, exercises, variants, programs, warm-up presets, and completed history merge by stable identity and logical revision. Each device writes its own replica. Deletion markers prevent stale copies from reviving removed records. Concurrent changes to the same record resolve deterministically; pre-merge recovery files retain the previous local version. A merge that breaks references is rejected for review and leaves local data intact. Import backup also accepts a device replica to recover its shared library.

Active workouts and device preferences stay local. Completed history merges after the active workout ends. Automatic backups include the active workout and settings, with a latest copy and 14 daily copies per device. Recovery keeps 30 pre-merge copies per device. Files are in `Lifting Sync/Devices`, `Backups`, and `Recovery` inside the chosen folder. Turning both switches off stops further automatic access; Disconnect folder releases the saved bookmark without deleting files.

Apple references: [directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories), [free iCloud storage](https://support.apple.com/en-us/108047). Native CloudKit instead requires an active Apple Developer Program membership and private data consumes the user's iCloud quota, so it was not chosen for this no-backend-cost implementation.

## Checks

```sh
./scripts/check.sh
```

This compiles and runs the actual XCTest case bodies with a small compatibility harness, including on machines without Xcode. With Xcode, run the Lifting scheme's tests normally.

The current host's Command Line Tools contain mismatched public and private SwiftPM interfaces. The Mac build was verified using a workspace copy of ManifestAPI with the stale private interfaces removed. No system toolchain files were changed. A normal Xcode installation should use the commands above directly.

See `VERIFICATION.md` for completed checks and remaining device checks. `DESIGN.md` describes the current UI; `RESEARCH.md` lists its references.
