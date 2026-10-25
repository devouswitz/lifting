# Setform

Native SwiftUI workout tracker. iOS 17 or later. Offline by default, with optional backup and sync through a user-selected folder. No app accounts, subscriptions, external packages, or hosted backend.

## Run on iPhone

1. Install Xcode, then add an iOS simulator runtime or connect an iPhone.
2. Open `Lifting.xcodeproj`.
3. Select the Setform target and your signing team under Signing & Capabilities. Keep the existing bundle identifier when updating an installed copy.
4. Choose the Setform scheme and your device, then Run.

The app retains `local.lifting.app` and its existing storage locations so updates preserve installed data. The project directory and core module keep their original names for compatibility.

## Mac preview

Open the included `Setform.app`, or build with:

```sh
./scripts/build-mac-preview.sh
```

The preview runs the same SwiftUI views and training engine. It does not replace testing on an iPhone.

For sample history without saving any changes:

```sh
open -n '../Setform.app' --args --demo
```

`--showcase` loads a fuller sample instead: a finished 5/3/1 block and four months of Push Pull Legs, used for screenshots and the demo video.

## Controls

- Train: the loaded program's next day with Start, its later days in the order they come up, and Start Empty Workout. Tap the program row to switch programs or open one. Each program remembers its place. Completing another day does not skip the next one. Skip Workout in the next day's menu saves it to History with every set unchecked and moves on. Reorder days in the program editor.
- Programs: tap a program to load it, or its info button to edit days, order, and notes. Add Day creates a day inside that program. Import Day copies selected days from another program or Saved Days with independent prescriptions and tracking. Programs > Saved Days retains reusable templates, including creation, reordering, duplication, deletion, and CSV export. New Program can optionally start with saved days. Hold a program for Duplicate or Delete; these actions also remain in its details. Reorder appears when multiple programs exist.
- Day editor: notes above workout-style cards with independent set weights, warm-up percentages, and per-set targets. One Add Exercises button opens the picker directly. Tap an exercise to add it and return, or choose Select Multiple for ordered batch addition. Plan Settings contains progression, rounding, and track naming; set details and warm-up presets remain on the primary card. Each exercise menu opens its current superset or circuit for editing or unlinking.
- Prescription: configure working load, each set, percentage warm-ups, rep ranges, AMRAP, time, distance, RPE, rest, notes, and optional progression.
- Set targets: choose No count for RPE-only sets, Reps for a fixed target, Rep range for minimum and maximum reps, or AMRAP with an optional goal (shown as 5+). AMRAP and range sets start with no reps filled in and can be checked off without a count; completed AMRAP sets count as met for progression. Warm-ups can use a percentage of the working set.
- Workout: tap the check to log a set, or tap a value for the large keypad and confirm with its checkmark; confirming a rep count (checkmark or Next Set) also completes the set and starts rest. Tap Rest to change rest between sets on an m:ss keypad with 1:00 to 5:00 presets; every duration in the app uses it. The weight summary is read-only and shows a range when sets differ. Swap Exercise is in each exercise's menu.
- Equipment: the equipment menu under each exercise switches to the same movement on other equipment (Barbell, Dumbbell, Cable, Machine, Smith Machine, Kettlebell, Band, Bodyweight), creating that version the first time. Exercises are grouped by name, so existing ones such as Bench Press and Dumbbell Bench Press join automatically. Each version keeps its own history. In a workout it swaps for today, like Swap Exercise; in a day editor it changes the saved day.
- Bodyweight exercises: the +lb column records added weight, or negative weight for assistance (the keypad's ± key); empty means bodyweight only. Log body weight in Progress > Body Weight; the weigh-in in effect when a workout ends gives bodyweight sets their load for volume and estimated max, and corrections update past workouts.
- Substitute: choose Today only or Future sessions, then an exercise. Completed sets stay on the original exercise. Future changes affect this day slot only.
- Drop and MYO: tapping the Drop or MYO button adds the chain at once using your setup: reductions, number of drops, and drop targets; or activation target, mini-set count, mini-set target, and rest. Hold the button and choose Drop Setup or MYO Setup to change it before applying, replace remaining work sets, save to the day, or keep the setup for this exercise or for all exercises. Settings > Set Types > Drop or MYO edits the app-wide setup. Choosing Drop or MYO on a set badge converts that set: a drop takes the drop percentage of the previous set with no rest before it; MYO makes it the activation set and adds mini-sets. A mini-set logged below its target ends the cluster: the pending mini-sets after it are removed and normal rest follows. Add Mini-set continues a cluster. Recurring drop loads stay relative to working weight.
- Drop/MYO targets use the same exact reps, rep ranges, no-count, RPE, time, and distance controls as ordinary sets. Percentage fields accept typed values and 5-point adjustments. Failure is also available as a set type.
- Superset / Circuit: link two or more exercises in a day editor or live workout. Choose transition and round rest. Logging advances the focused panel around the group; warm-ups and drop/MYO chains finish before moving on. Uneven set counts skip completed movements. Live links can be saved to the day.
- Warm-up presets: create named, ordered schemes in Settings, or save a prescription's current warm-ups. Apply a preset to selected day exercises or live exercises. Replace or append warm-ups, and optionally save live changes to the day variants. Completed warm-ups are retained. Presets copy their plans, so editing a preset does not rewrite existing days.
- Save to this day: makes live load, drop/MYO, warm-up, or link changes recur. Otherwise they apply to the current workout.
- Tap an exercise header to expand or collapse it. Opening one focuses that exercise. Warm-ups and working sets have separate compact tables. Completed exercises collapse by default; Settings can turn this off. Hold an exercise header and drag to reorder it in a day or workout. Move Up and Move Down remain accessibility actions on the header. Workout options include Collapse All and Expand All.
- Set values: tap to edit one actual value. Hold the reps field to edit its exact/range/AMRAP target. Hold the set badge for Set Details, including load rules, RPE, time, distance, and rest. The badge also offers Set Details by tap. Logged time and distance remain editable in live set details. Swipe left to reveal Delete, or continue swiping to delete. Range targets never assume an exact rep count; unknown reps do not contribute to volume, estimated max, or progression.
- Exercise categories: choose equipment and muscles from searchable categories, or create a custom category. Custom choices are reused across the exercise library and travel with existing backups and sync. Existing imported labels remain intact.
- Editing: existing records retain valid edits on Done (the checkmark), Back, or sheet dismissal. New records use Create; batch and technique changes use Add or Apply. Dismissing a technique preview does not apply it. Incomplete edited drafts require correction or Cancel. Live workout logging remains immediate. Keypads offer Previous Set and Next Set, committing edited values without reopening; visiting an inherited weight leaves it inherited.
- Set controls: tap the set badge to change type. Hold the badge for details, reps for the target mode, or weight for load settings. Template range editing keeps both bounds and offers a separate Exact reps entry. Tap a template set badge for Duplicate Set; Reorder Sets in its exercise menu exposes drag handles and accessible move actions. Hold either quick-action button to assign any supported or custom set type, or to open the Drop or MYO setup; the two slots are shared by templates and workouts.
- History comparisons use equal elapsed days for an unfinished period and show their exact dates. Rest days show No data when a period has no recorded history; future days are excluded.
- Independent weights: later untouched working sets follow the nearest earlier explicit entry, in both days and active workouts. Entering 100, then 110 in the next set gives 100/110/110; changing the first to 105 keeps 105/110/110. Fixed loads, completed sets, and later explicit entries are preserved. Percentage warm-ups follow the first working set. Save Weights to This Day in the exercise menu saves the individual loads and inheritance. Native number fields select their contents on first focus and support paste; the entire form row focuses its field.
- Pause Workout stops duration, exercise timers, and rest. Resume continues elapsed active time. With notification permission, unfinished workouts remind after 45 minutes without changes, or 30 minutes paused, with one follow-up 90 minutes later. Finishing, discarding, or disabling reminders cancels them. The rest timer's − and + buttons default to 15 seconds; hold either to change the step, also in Settings > Workout.
- History: browse dated results or a monthly calendar. Tap a day to see its workouts. The comparison covers the past week, month, three months, or year against the period before, including average volume per muscle. Rest days count only days that have passed. Open a workout to inspect or edit its sets and notes; swipe a set in Edit to delete it.
- Progress: choose a program or All programs, then compare separate exercise and day tracks, choose a metric and date range, or scrub a graph for actual recorded values. Exercise details include dated results. Hide an exercise you no longer do from its menu or by long-pressing its record; Hidden exercises lists them to show again.
- Progress > Body Weight: log weigh-ins with a date, see the trend for the chosen range, and tap an entry to correct or delete it. Weigh-ins are included in backups and device sync.
- Progress > Muscles: compare logged sets or load volume by primary muscle, with optional half-set credit for secondary muscles. Program and date filters apply. Warm-ups and cardio are excluded; drop/MYO sets count individually. Unknown rep counts contribute no invented volume. Muscle assignments can be edited with an exercise; new sessions snapshot them.
- Settings: units, appearance, and colors, workout preferences, plate sizes, Apple Health, folder backup/sync, JSON backup/restore, and CSV import/export.
- Set types: Settings > Set Types lists the built-in types (Warm-up, Working, Drop, MYO, Failure) and custom ones. A custom type has a name, a 1-3 character badge, an optional color, and counts as a working set, warm-up, or failure set, which decides volume, records, progression, and warm-up handling. Custom types appear in set-type choices, configurable quick-add buttons, history, CSV, backups, and sync. Changing what a type counts as updates saved prescriptions; deleting one leaves its sets counting the same way under the built-in name.
- Quick-add buttons: the two buttons next to Add Set in a workout default to Drop and MYO. Long-press either to open its setup or swap it for Drop, MYO, Warm-up, Failure, Working, or a custom type; the choice applies to every exercise and can also be set in Settings > Set Types.
- Exercises: Programs > Exercises lists every exercise; New Exercise adds one without putting it in a day, and tapping one edits it.
- Support: Settings ends with a Ko-fi link.
- Colors: each color role (Action, Completed, Warm-up, Drop and MYO, Failure, Rest and time, Best, Background, Cards, Fields) can be set separately for light and dark mode, with a live preview. Colors are a device preference and are included in JSON backups.

Weights are stored in kilograms and converted for display. Warm-up and drop percentages round down to the variant's increment. RPE is a user-entered target or observation.

## Data

Data is stored as an atomic, versioned JSON file in the app's Application Support directory. The previous valid save is kept as `training.json.previous`. Backup replacement preserves the pre-import state as `training.json.before-import`. Corrupt files are not silently replaced with starter data.

Completed sessions snapshot program and day names, prescriptions, notes, and values. History uses Program - Day titles. Day and program edits do not rewrite history. Exercise identity and variant identity are separate. Progression applies only to the relevant variant and requires all non-warm-up sets to be complete.

Deleting the app removes its on-device data. Export backups to a location you control.

## Sharing CSV

Export CSV from a day/template or program editor. Import CSV from Train, Programs, or Settings. Review the preview, then Add or Add and Load. Imports create independent copies and preserve existing data.

Day/program CSV carries ordered days and exercises, working loads and per-set overrides, relative warm-up/drop formulas, MYO sets, targets, rest, notes, groups, and progression rules. A minimal hand-edited CSV needs `day,exercise` columns. Use an exported file as the full schema; weight columns ending `_kg` use kilograms, time uses seconds, and distance uses meters. UTF-8, quoted multiline fields, comma and semicolon separators are supported. Invalid files are rejected before changing data.

Logged-set CSV is a separate format for history, with actual values, rep-range targets, program identity, notes, times, pause intervals, linked groups, muscle snapshots, source fields, and stable IDs. Reimporting the same workouts skips duplicates. Legacy Lifting CSV is accepted with inferred exercise types and no duration. JSON backup is the complete device backup, including active workouts, settings, and warm-up presets.

## Importing other apps

Settings > Import workout data detects Strong, Hevy, and FitNotes CSV headers. Confirm unspecified units, date format, and column assignments, then review the workouts before adding them. Other CSVs can use the same column mapper. Flat set-record JSON and Hevy-style nested workout/exercise/set JSON are also supported. No login, API key, or server is required.

Imports preserve units, actual values, supported set types, notes, groups, available duration, and source fields. Familiar exercise names with equipment suffixes can map to the existing catalog; day-specific tracks remain separate. Reimporting an unchanged export skips its workouts. Optionally build a program from each latest logged day. These reconstructed days use exported results; the file cannot supply saved prescriptions or progression rules that the source app omitted. Ambiguous dates, invalid values, encrypted files, and proprietary database backups are rejected rather than guessed. GreySkull-specific binary/cloud backup formats have not been validated.

## Apple Health

Two switches in Settings, both off initially.

- Add Calories from Apple Health reads workouts from the last 60 days. A workout from another source (an Apple Watch, the Fitness app, another app) is matched to a Setform session when at least half of it falls within the session, give or take 10 minutes. The session's log then shows its active calories and average heart rate, for example "412 kcal · 128 bpm average · Apple Watch". Lifting and cardio work in any order:
  - A strength workout and a run recorded separately on the watch during one Setform session both count; the workout's detail lists each with its time and calories.
  - One watch workout left running across two Setform sessions (a lift, then a separate cardio session) is split between them by when the energy was burned, using the watch's per-minute samples, so no calorie counts twice. The values stay in Setform's log if Health access is later turned off. A wrong match can be removed in the workout's Edit screen.
- Save Workouts to Apple Health writes a workout for a finished session only for active time nothing else recorded. Pauses are excluded. If the watch recorded only the run at the end, Setform saves the lifting before it, so Fitness shows both without overlap. Gaps shorter than 5 minutes beside another recording are not saved. A session of only cardio exercises is saved as that activity (Run, Walk, Cycling, Rowing, Stairs, Elliptical, Swim, or Cardio); anything with lifting is saved as strength training. Setform waits 10 minutes after Finish for a watch workout to reach the phone first. If a watch workout for the same time shows up later, Setform deletes its own copy (or trims it to the time still uncovered) and takes the watch's calories. Saving starts with sessions finished after the switch is turned on; old history is never copied.

Setform never edits or deletes a workout it did not save. HealthKit only allows an app to delete samples that app wrote, and Setform also checks the source before any deletion. Deleting a session in History also deletes the copy Setform saved for it. Health values are not written to the sync or backup folder, which may be iCloud Drive; each device reads them from Apple Health. Exported JSON backups and logged-set CSV keep them.

Apple Health is iPhone only; the Mac preview hides these settings. Running from Xcode needs the HealthKit capability on your signing team, which `Resources/Lifting.entitlements` declares.

## Optional folder backup and sync

In Settings, choose the same iCloud Drive folder on each device. Automatic backup and Device sync are separate switches, both off initially. A local folder works for backup; cross-device transport requires iCloud Drive or another folder provider. This approach needs no CloudKit container or backend subscription. iCloud includes 5 GB free, shared with the user's other iCloud data; extra storage is not free.

The app checks the folder while open, after changes, and on foreground activation. OS/provider upload and download timing is outside the app's control. Routines, exercises, variants, programs, warm-up presets, and completed history merge by stable identity and logical revision. Each device writes its own replica. Deletion markers prevent stale copies from reviving removed records. Concurrent changes to the same record resolve deterministically; pre-merge recovery files retain the previous local version. A merge that breaks references is rejected for review and leaves local data intact. Import backup also accepts a device replica to recover its shared library.

Active workouts and device preferences stay local. Completed history merges after the active workout ends. Automatic backups include the active workout and settings, with a latest copy and 14 daily copies per device. Recovery keeps 30 pre-merge copies per device. Files are in `Lifting Sync/Devices`, `Backups`, and `Recovery` inside the chosen folder. Turning both switches off stops further automatic access; Disconnect folder releases the saved bookmark without deleting files.

Apple references: [directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories), [free iCloud storage](https://support.apple.com/en-us/108047). Native CloudKit instead requires an active Apple Developer Program membership and private data consumes the user's iCloud quota, so it was not chosen for this no-backend-cost implementation.

## Checks

```sh
./scripts/check.sh
```

This compiles and runs the actual XCTest case bodies with a small compatibility harness, including on machines without Xcode. With Xcode, run the Setform scheme's tests normally.


See `VERIFICATION.md` for completed checks and remaining device checks. `DESIGN.md` describes the current UI; `RESEARCH.md` lists its references.

## Release validation

Export using the existing App Store Connect app and signing team. Verify the actual signed package before uploading:

```sh
python3 scripts/verify-ipa.py /path/to/Setform.ipa --build 5
```

A build produced with `CODE_SIGNING_ALLOWED=NO` does not carry signed entitlements. Before distribution export, sign its embedded frameworks and app locally, with `Resources/Lifting.entitlements` on the app, so Xcode preserves HealthKit while applying distribution signing. The exported IPA must pass the capability check above. Keep the bundle identifier and storage paths unchanged for updates.
