# Interface

## Structure

One pattern per job. Pushed screens are for browsing and managing (Programs, a program, a day, an exercise's progress, a past workout). Sheets are for focused create or edit tasks with Cancel and Save. The active workout is full screen. A chevron.right opens a screen, chevron.up.chevron.down opens a choice menu, and an ellipsis holds every action for the object it sits on. "Add" rows sit inside the list they add to. No icon-only toolbar menus mix unrelated actions.

## Train

Train shows the loaded program as one row that opens Programs, the next workout as the main card (exercises with set × rep targets and working weights, and Start or Resume), the program's later days in the order they come up, and Start Empty Workout. Each day has one menu: Skip Workout (next day only) or Make Next Workout, Move Earlier/Later, Duplicate, Save as Template or Add to Program, Export CSV, and Delete. Move Earlier/Later works on the upcoming order, so moving the next day later makes the following day next. Finishing or discarding a workout returns Train to its first screen. Programs lists every program (tap to load, info button to open) and day templates; Edit reorders and deletes both, and rows swipe to Delete or Duplicate. Program and day editors show the name as the screen's large title, which is edited in place, followed by their lists and a Notes section.

## Workout

During a workout, each exercise is a collapsible card. Opening one closes the others. The card header shows the exercise, progress, and its menu (Swap Exercise first). Below it, "Working 95 lb" and "Rest 3:00" are tappable values, then an inline note field. One column header covers the table; Warm-up and Working sets are labelled groups inside it. Rows show previous values, editable actual values, RPE, and a check that fills the row with the Completed color. Add Set, Drop, and MYO sit under the table. Collapse after completion is opt-in. Rep target choices are No count, Reps, and Rep range for every set type. Values are entered on a compact keypad sheet that names the exercise and set; the first key replaces the shown value. The rest timer floats above the bottom edge with a progress ring. While minimized, the workout sits in the tab bar accessory on iOS 26.1 and later.

## History

Log shows month-grouped workouts with Program - Day titles and actual exercise results. Program names are captured when the workout starts. Calendar shows workout dates (skipped days as a dashed ring) and the selected day's workouts; the full list stays in Log. Its comparison covers the past week, the month (default), three months, or a year, chosen by tapping the compared period, and ends with average volume per workout for each primary muscle. Workout detail uses read-only set tables; Edit opens the existing date, notes, and set controls. Exercise titles link directly to the relevant progress track.

## Progress

The first screen is a multi-exercise chart with program, exercise, metric, and range filters. Program selection scopes both charts and records, and remains in scope when opening exercise detail. Each day variant has its own series. Records contain only logged exercises and numeric results, without miniature graphs. Exercise detail offers separate tracks, latest/best/change values, dated results, and notes. Scrubbing a chart displays actual values from a recorded session.

## Storage and identity

All state stays in local JSON. Exercise definitions and day variants have separate IDs. Substitutions retain a stable family so returning to an exercise resumes its original track. New day copies and imported routine copies get independent tracks. History CSV maintains import mappings across backups and incremental imports.

## Apple Health

Apple Health is the record of what the body did; Lifting is the record of what was lifted. Lifting reads a workout recorded by another source and copies its calories and heart rate into the matching session, so the Health workout stays exactly as the watch saved it and Fitness never shows a second entry. Lifting writes its own workout only when no other source recorded that time, and removes it if one appears later. Matching lives in `LiftingCore/HealthLink.swift` and is covered by core tests; `LiftingApp/HealthBridge.swift` only reads, saves, and deletes Lifting's own samples.

## Appearance

Every color has one meaning, used the same way on every screen:

- Action (blue): buttons, links, selected tabs.
- Completed (green): checked sets, whose row also turns green; finished exercises; workout days in the calendar.
- Warm-up (orange): W badges and the Warm-up table header.
- Drop and MYO (purple): D, A, and M badges, the Drop and MYO buttons, superset labels.
- Failure (red): F badges.
- Rest and time (teal): the rest bar, rest durations, per-set rest.
- Best (gold): best results in Progress.
- Background, Cards, Fields: the neutral surfaces.

Defaults are Apple system colors tuned separately for light and dark. Settings > Colors edits each role for each appearance, with a live preview, and can reset one role, one appearance, or everything. Chart series use hues no role claims.

Type is SF Pro with tabular figures for weights, reps, and times. Hierarchy comes from weight and size: the next day is the main card on Train, and the other days share one grouped list. Set tables use filled value fields, colored set badges, and a filled check that turns the row green.
