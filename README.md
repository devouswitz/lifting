# Lifting

Native SwiftUI workout tracker. iOS 17 or later. No accounts, network calls, analytics, subscriptions, or external packages.

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
- Workout: tap the checkbox to log a set, tap a value to edit, tap the working load to update remaining work and percentage warm-ups.
- Substitute: choose Today only or Future sessions, then an exercise. Completed sets stay on the original exercise. Future changes affect this day slot only.
- Drop: choose reductions, number of drops, and reps. Recurring drop loads stay relative to working weight.
- MYO: choose activation reps, mini-set count, mini-set reps, and rest. Replace remaining work sets if desired. Add mini-sets, change values, or remove sets during the workout.
- Save to this day variant: makes live load or drop/MYO changes recur. Otherwise they apply to the current workout.
- Tap an exercise header to expand or collapse it. Opening one focuses that exercise. Warm-ups and working sets have separate compact tables. Automatic collapse after completion is optional in Settings. Workout options include Collapse All and Expand All.
- Each set's menu edits today's targets, load rule, percentage, type, and rest. Tap a value to edit the actual result.
- History: browse dated results or a selectable monthly calendar with comparisons to the previous month. Open a workout to inspect or edit its sets and notes.
- Progress: compare separate exercise and day tracks, choose a metric and date range, or scrub a graph for actual recorded values. Exercise details include dated results.
- Settings: units, appearance, rest preferences, plate sizes, JSON backup/restore, and CSV import/export.

Weights are stored in kilograms and converted for display. Warm-up and drop percentages round down to the variant's increment. RPE is a user-entered target or observation.

## Data

Data is stored as an atomic, versioned JSON file in the app's Application Support directory. The previous valid save is kept as `training.json.previous`. Backup replacement preserves the pre-import state as `training.json.before-import`. Corrupt files are not silently replaced with starter data.

Completed sessions snapshot names, prescriptions, notes, and values. Day and program edits do not rewrite history. Exercise identity and variant identity are separate. Progression applies only to the relevant variant and requires all non-warm-up sets to be complete.

Deleting the app removes its on-device data. Export backups to a location you control.

## Sharing CSV

Export CSV from a day/template or program editor. Import CSV from Train, Programs, or Settings. Review the preview, then Add or Add and Load. Imports create independent copies and preserve existing data.

Day/program CSV carries ordered days and exercises, working loads, relative warm-up/drop formulas, MYO sets, targets, rest, notes, groups, and progression rules. A minimal hand-edited CSV needs `day,exercise` columns. Use an exported file as the full schema; weight columns ending `_kg` use kilograms, time uses seconds, and distance uses meters. UTF-8, quoted multiline fields, comma and semicolon separators are supported. Invalid files are rejected before changing data.

Logged-set CSV is a separate format for history, with actual values, notes, times, and stable IDs. Reimporting the same workouts skips duplicates. Legacy Lifting CSV is accepted with inferred exercise types and no duration. Other apps' proprietary CSV formats are not currently mapped. JSON backup is the complete device backup, including active workouts and settings.

## Checks

```sh
./scripts/check.sh
```

This compiles and runs the actual XCTest case bodies with a small compatibility harness, including on machines without Xcode. With Xcode, run the Lifting scheme's tests normally.

The current host's Command Line Tools contain mismatched public and private SwiftPM interfaces. The Mac build was verified using a workspace copy of ManifestAPI with the stale private interfaces removed. No system toolchain files were changed. A normal Xcode installation should use the commands above directly.

See `VERIFICATION.md` for completed checks and remaining device checks. `DESIGN.md` describes the current UI; `RESEARCH.md` lists its references.
