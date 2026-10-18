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

- Train: start, create, duplicate, edit, reorder, or remove routines. Adding an exercise creates an independent variant for that routine.
- Prescription: configure working load, each set, percentage warm-ups, rep ranges, AMRAP, time, distance, RPE, rest, notes, and optional progression.
- Workout: tap the circle to log a set, tap a value to edit, tap the working load to update remaining work and percentage warm-ups.
- Substitute: choose Today only or Future sessions, then an exercise. Completed sets stay on the original exercise. Future changes affect this routine slot only.
- Drop: choose reductions, number of drops, and reps. Recurring drop loads stay relative to working weight.
- MYO: choose activation reps, mini-set count, mini-set reps, and rest. Replace remaining work sets if desired. Add mini-sets, change values, or remove sets during the workout.
- Save to this routine variant: makes live load or drop/MYO changes recur. Otherwise they apply to the current workout.
- Each set's menu changes its type or removes it. Its context menu also exposes time, distance, and rest.
- Progress: select an exercise, variant, metric, and date range. All variants draws separate series. Sessions beneath the graph provide the same data as readable text.
- Settings: units, appearance, rest preferences, plate sizes, JSON backup/restore, and CSV export.

Weights are stored in kilograms and converted for display. Warm-up and drop percentages round down to the variant's increment. RPE is a user-entered target or observation.

## Data

Data is stored as an atomic, versioned JSON file in the app's Application Support directory. The previous valid save is kept as `training.json.previous`. Imports preserve the pre-import state as `training.json.before-import`. Corrupt files are not silently replaced with starter data.

Completed sessions snapshot names, prescriptions, notes, and values. Routine edits do not rewrite history. Exercise identity and variant identity are separate. Progression applies only to the relevant variant and requires all non-warm-up sets to be complete.

Deleting the app removes its on-device data. Export backups to a location you control.

## Checks

```sh
./scripts/check.sh
```

This compiles and runs the actual XCTest case bodies with a small compatibility harness, including on machines without Xcode. With Xcode, run the Lifting scheme's tests normally.

The current host's Command Line Tools contain mismatched public and private SwiftPM interfaces. The Mac build was verified using a workspace copy of ManifestAPI with the stale private interfaces removed. No system toolchain files were changed. A normal Xcode installation should use the commands above directly.

See `VERIFICATION.md` for completed checks and remaining device checks. `DESIGN.md` records the Claude Opus UI specification; it includes design proposals beyond the implemented features.
