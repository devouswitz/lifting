# Verification

Verified on October 18, 2026.

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

- 40 core test cases, zero failures. The standalone harness runs the same test bodies as the Xcode XCTest target.
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

Not included: Apple Watch support, Health integration, superset management, variant merging, schedule calendars, or equipment-specific inventory counts.
