# Verification

Verified on October 18, 2026.

## Polish and parity pass

- Parity: warm-up, working, drop, MYO, and failure sets all use the same target editor (No count, Reps, Rep range, AMRAP, RPE, time, distance, rest). Checked natively on a warm-up set. The live set menu is now identical whether opened by tapping the set badge or long-pressing the row. Previously each opened a different subset of actions.
- Prescription editor: Add Working Set copies the last working set's targets instead of a fixed 8-12 default. Add Warm-up Set goes after the existing warm-ups instead of at the top, matching the live workout. Rows show the resolved load, for example 47.5 lb (50%) × 5, using the live W1/1 badges. Checked natively.
- Fixes: the history calendar counted the rest of the current month as rest days (24 on Oct 18; now 11). The workout name field could not be cleared and retyped. Discard confirmation now appears inside the Finish sheet rather than after it closes. The working-weight sheet stays open on a failed apply. History edit allows deleting a logged set.
- Train: shows Resume Workout during an active workout instead of disabled Start buttons. Days without exercises show Add Exercises. The resume bar sits above the tab bar; it was below it on Mac. Checked natively.
- Copy: removed duplicated or filler text, including the repeated track chip on every exercise row in a day, Settings footnotes, and "day variant" jargon. Menus and buttons use consistent title case and icons.
- 59 core test cases, zero failures. Mac release build verified with Command Line Tools.
- Not verified: iOS compilation and iPhone layout, including the per-tab resume bar placement on iOS. Xcode was installed during this pass but its license had not been accepted, so no simulator run was possible.

## Linked training, presets, analytics, imports, and optional sync

- Core coverage now includes linked warm-up sequencing, transitions, round rest, uneven set counts, drop/MYO chains, unlinking/undo behavior, substitution, template copies, CSV/JSON persistence, named warm-up copies, live replacement retaining completed sets, and optional future scope.
- Native Mac: linked Bench press and Barbell row with 75-second round rest. Applied the named Descending preset (80%, 60%, 40%) to the Upper day. Warm-ups resolved against each exercise's working weight. Completing each movement's warm-ups focused the next warm-up panel; working sets alternated panels and started a 1:15 timer after a round.
- Native Mac: typed a 12.5% drop reduction and selected a 12-15 rep range. Preview showed 87.5% of working weight. Adding it live created an 82.5 lb drop from 95 lb, with optional actual reps. Live reapplication of a warm-up preset retained three completed warm-ups and the completed working set, replaced pending warm-ups, and left recurring prescriptions unchanged.
- Native Mac: created and saved the Descending preset through the set editor. The library exposed named presets, and program/day/live application used independent copies. Native data read-back confirmed percentages, completed sets, round rest, and drop targets.
- Muscle analytics rendered labeled bar charts and numerical distribution for logged sets and load volume, using program/date filters. Core checks cover warm-up/cardio exclusion, secondary half-set credits, muscle snapshots, and missing exact counts contributing no volume.
- External import checks cover Strong, Hevy, FitNotes, mapped CSV, flat/nested JSON, units, notes, durations, set types, source fields, deterministic duplicate detection, exercise matching, day-track independence, and program reconstruction. Native Strong import added a workout and reconstructed program while preserving existing data. The history title included the new program name.
- Native units check: selected kg for a Strong file with unspecified units. The expanded preview showed 60 kg as 132.3 lb and 45 kg as 99.2 lb. Saved data retained 60/45 kg, and program reconstruction used a 60 kg working load and 75% drop. The shared percentage editor rendered its typed value and stepper without duplicate field labels. Folder access survived relaunch, and its picker opened and canceled as one sheet.
- Native optional backup/sync: both switches began off. Selected a dedicated local test folder, enabled them, and verified a latest backup, daily backup, and per-device replica on disk. A second replica added a workout and named warm-up preset. The app deferred merging during an active workout, then retained both completed histories (33 workouts total), imported the second preset, kept lb as the local unit, and wrote recovery copies. Active-workout backups included the current checked sets and live-only edits.
- Core sync checks cover independent changes, deterministic concurrent resolution, tombstones, stale replicas, local preferences, warm-up presets, and atomic rejection of broken cross-record references. Same-record conflicts use one whole-record revision; recovery copies preserve the previous local state.
- All native feature checks used an isolated demo data directory. The regular user library and its optional-sync preferences were not changed.

Actual iCloud transport and physical multi-device delivery remain unverified. The native file picker reported insufficient iCloud upload quota on this account. Folder backup/merge behavior was tested through a local folder and two independent replica identities. iOS compilation and device checks remain deferred as below.

## Target and program refinements

- Explicit No count, Reps, and Rep range controls in the shared prescription/live target editor. Native warm-up editing changed 50% to 65% of 95 lb, resolving to 60 lb after rounding.
- Native range logging: one 8-10 target completed with no exact count; a second set recorded 9. The saved volume was 585 lb, counting only 65 × 9. An RPE-only set with no load or reps saved successfully.
- Native program filtering: selecting Test Program showed only its two logged exercises, including a 7 RPE record. Starter history stayed independent. The record sparklines were removed.
- Native history showed Test Program - Upper and Starter - Push titles. Rep ranges and optional exact counts appeared separately in the saved results.
- Core tests cover range-only and RPE-only completion, optional count entry, no invented volume or progression, target/actual separation when adding and substituting sets, program scope, snapshot names after program rename/removal, and CSV/JSON compatibility.

## Current redesign

- The official GreySkull LP by Nazim Ashraf App Store screenshots guided history and graphs. The current redesign used Codex implementation agents and direct native verification.
- Simplified Train: separate Program/Templates views, no duplicate next-day card, compact day previews, direct Start controls. Creating a custom template opens its editor.
- Native live panels: warm-ups and working sets are separate tables; completing five Bench press sets keeps the panel open by default. Opening Barbell row closes Bench press and preserves all five results. Live Drop and MYO controls create the expected rows and allow completion and notes.
- Native history: monthly calendar, previous-month deltas, selected-day filtering, dated exercise results, compact set details, editing, and a saved dated exercise note were checked. A graph link opens the corresponding day track.
- Native progress: separate Upper and Push lines, an independent newly recorded program track, latest/best/change values, date ranges, cardio minutes, and recorded-session values selected by clicking the chart were checked. Lines do not join independent variants.
- Native JSON and CSV import were both exercised from Settings after separating their picker presentation anchors. JSON restored the active workout; CSV previewed one program, three days, and 21 sets, then added and loaded it while preserving the active workout.
- Native substitution: Cable to Dumbbell to Cable restored the original 10 lb prescription and dated note, without borrowing an unrelated same-label 80 kg prescription.
- Dark home, workout, and chart layouts and both light and dark calendars inspected. History set rows expose one accessibility summary per row.
- Core regression coverage includes substitution families, copied-day independence, incremental history imports across backup/reload, older import mapping recovery, live-added exercise day scope with unsorted historical dates, and manual collapse state preservation.

## Earlier feature checks

- 59 core test cases, zero failures. The standalone harness runs the same test bodies as the Xcode XCTest target.
- Native macOS release build using the same SwiftUI views and training engine as the iOS target.
- Native UI: one-tap set completion, fractional weight editing, automatic rest, live drop sets, live MYO activation and mini-sets, changing mini-set count and rest, saving MYO settings to a single routine variant.
- Native UI and persisted file read-back: active workout survives process termination and relaunch with completed sets and MYO settings intact.
- Native UI and persisted file read-back: finish saves the workout and notes, then advances the next program day.
- Native graphs: Upper and Push cable lateral raise series displayed together; selecting Upper filters both the graph and session list to that variant.
- Native JSON export: the resulting file contained all 31 test sessions, the saved workout note, and the recurring MYO prescription.
- Native JSON import: the app previewed the correct counts, restored the exported data, and preserved the pre-import state in a separate local file.
- Native cardio: a timed run inside Lower starts, logs elapsed time, completes its set, and saves a dated exercise note.
- Light and dark layouts inspected in the native app.
- Xcode project and privacy manifest pass plist validation. The app icon is an opaque 1024 × 1024 RGB PNG.
- Preview binary links only Apple system libraries and frameworks. App source has no networking client or third-party dependencies.

- Native program UI: create and load a custom program from Upper/Lower templates; clear and replace its name; add a blank Sprints day; add a cardio exercise; save that day as a template.
- Native CSV export/read-back: the custom program file contained all three days, seven exercise slots, 21 prescribed sets, and four percentage warm-ups.
- Native CSV import: preview showed the correct program/day/set counts; Add and Load created a new program with disjoint day/variant IDs and preserved the 30 existing test sessions.
- Native collapse: completing all five Bench press sets collapsed its card, expanded Barbell row, and retained all completed values. Collapse All and manual reopening worked. The same states survived process termination and resume.
- Native live targets: changed one Barbell row set to 80% working weight, RPE 7, and 15 seconds rest. Persisted read-back confirmed the current workout changed while the saved variant retained its original targets.
- Native final toolbar: workout options and Finish are both visible; saving the workout advances the imported program to Lower. Loading Starter and switching back retained the imported program's second-day position.
- Native error recovery: importing a malformed CSV from the Programs sheet displayed its error inside that sheet and preserved program/history data.

Current redesign tests used `--demo` in memory. Earlier feature tests used isolated `--demo --data-directory <test-folder>` data. Regular launches do not load test sessions. A CLI-seeded file under the iCloud Documents workspace stalled during startup file access; importing that same file through the native picker succeeded. User data was not changed by these tests.

## Not yet verified

- iOS compilation, simulator execution, iPhone layout, keyboard behavior, Dynamic Type extremes, device haptics, background notification delivery, and signing.
- Xcode is absent on this Mac. Only Command Line Tools and the macOS SDK are installed. No iPhone SDK or simulator is available. The user chose to continue with the Mac preview; iPhone testing is deferred.

The iOS app is not installed on an iPhone or distributed through TestFlight or the App Store.

## Scope

The implemented app covers the requested substitutions, independent day variants, flexible warm-ups, per-exercise notes, local storage, mixed cardio, drop sets, and MYO reps. It also includes ordered programs, reusable day templates, independent copies, day/program CSV sharing, additive history CSV import, editable exercises, rest timers, plate calculation, progression rules, graphs, history editing, and backup/restore.

Not included: Apple Watch support, Health integration, variant merging, schedule calendars, or equipment-specific inventory counts. Proprietary/encrypted competitor backups, including GreySkull-specific binary/cloud backup formats, have not been validated. Folder sync runs while the app is open; active workouts and device preferences do not merge across devices.
