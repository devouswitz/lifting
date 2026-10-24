# Interface

## Structure

One pattern per job. Pushed screens are for browsing and managing (Programs, a program, a day, an exercise's progress, a past workout). Sheets are for focused tasks. Existing records save valid changes on Close or dismissal without a redundant Save action. Create confirms new records; Add, Link, and Apply confirm batch commands. Dismissing a changed batch or technique preview does not execute it. Invalid edited drafts require correction or Cancel. Nested choices update the parent draft without committing it. The active workout is full screen. A chevron.right opens a screen, chevron.up.chevron.down opens a choice menu, and an ellipsis holds every action for the object it sits on. "Add" rows sit inside the list they add to. No icon-only toolbar menus mix unrelated actions.

## Train

Train shows the loaded program as one row that opens Programs, the next workout as the main card (exercises with set × rep targets and working weights, and Start or Resume), the program's later days in the order they come up, and Start Empty Workout. Each day has one menu: Skip Workout (next day only) or Make Next Workout, Move Earlier/Later, Duplicate, Save Day Copy or Add to Program, Export CSV, and Delete. Move Earlier/Later works on the upcoming order, so moving the next day later makes the following day next. Finishing or discarding a workout returns Train to its first screen. Programs lists every program, with Saved Days as a secondary library. Add Day creates a program-owned day; Import Day copies selected days from another program or Saved Days. Reusable templates retain all previous controls. Day editing uses the same collapsible cards and set fields as the live workout. A single exercise tap adds and returns immediately. Select Multiple adds exercises in the chosen order with one confirmation. Empty days keep notes and one direct Add Exercises control. Plan configuration excludes the duplicate set table; saved plans reuse the primary exercise card. Search is pinned above the picker list without overlapping its rows.

## Workout

During a workout, each exercise is a collapsible card. Opening one closes the others. The card header shows the exercise, progress, and its menu (Swap Exercise first). Below it, the working-weight summary reflects the actual sets and "Rest 3:00" is editable, then an inline note field. One column header covers the table; Warm-up and Working sets are labelled groups inside it. Rows show previous values, editable actual values, RPE, and a check that fills the row with the Completed color. Add Set and two configurable quick-action buttons sit under the table; the defaults are Drop and MYO. Templates and workouts share their assignments. Collapse after completion defaults on, while an explicit opt-out is preserved. Collapsed headers support native drag and drop; moves remain available through accessibility actions. Tap changes a single actual value. Holding the reps field opens No count, Reps, Rep range, and AMRAP. Holding the row opens Set Details with every advanced target retained. Swipe left grows the delete action; a full swipe removes the set. Pending working loads inherit from the nearest earlier explicit entry; fixed and completed loads never inherit subsequent changes. Values are entered on a compact keypad sheet that names the exercise and set; the first key replaces the shown value. The rest timer floats above the bottom edge with a progress ring. While minimized, the workout sits in the tab bar accessory on iOS 26.1 and later.

## History

Log shows month-grouped workouts with Program - Day titles and actual exercise results. Program names are captured when the workout starts. Calendar shows workout dates (skipped days as a dashed ring) and the selected day's workouts; the full list stays in Log. Its comparison covers the past week, the month (default), three months, or a year, chosen by tapping the compared period, and ends with average volume per workout for each primary muscle. Workout detail uses read-only set tables; Edit opens the existing date, notes, and set controls. Exercise titles link directly to the relevant progress track.

## Progress

The first screen is a multi-exercise chart with program, exercise, metric, and range filters. Program selection scopes both charts and records, and remains in scope when opening exercise detail. Each day variant has its own series. Records contain only logged exercises and numeric results, without miniature graphs. Exercise detail offers separate tracks, latest/best/change values, dated results, and notes. Scrubbing a chart displays actual values from a recorded session.

## Storage and identity

All state stays in local JSON. Exercise definitions and day variants have separate IDs. Substitutions retain a stable family so returning to an exercise resumes its original track. New day copies and imported routine copies get independent tracks. History CSV maintains import mappings across backups and incremental imports.

## Apple Health

Apple Health is the record of what the body did; Setform is the record of what was lifted. Setform reads a workout recorded by another source and copies its calories and heart rate into the matching session, so the Health workout stays exactly as the watch saved it and Fitness never shows a second entry. Setform writes its own workout only for time no other source recorded, and removes or trims it if one appears later. Each Health workout's calories go to the session it happened in; one spanning two sessions is split by its energy samples. Matching lives in `LiftingCore/HealthLink.swift` and is covered by core tests; `LiftingApp/HealthBridge.swift` only reads, saves, and deletes Setform's own samples.

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

## Lifecycle

Pause intervals are persisted and excluded from duration, CSV round trips, and Health writes. Reminder scheduling is serialized so a stale update cannot leave alerts behind after a workout ends. The app keeps its bundle ID, data directory, and sync folder paths across the Setform rename.
