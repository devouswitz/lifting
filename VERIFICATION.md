# Verification

Verified on October 18, 2026.

## Passed

- 33 core test cases, zero failures. The standalone harness runs the same test bodies as the Xcode XCTest target.
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
- Two Luna testers reviewed core behavior and UI source, followed by adversarial checks and a second UI review. Their actionable name-editing, ordering, VoiceOver, and sheet-error findings were addressed. Their reviews do not replace device testing.

Native test data was isolated with `--demo --data-directory <test-folder>`. Regular launches do not load those test sessions.

## Not yet verified

- iOS compilation, simulator execution, iPhone layout, keyboard behavior, Dynamic Type extremes, device haptics, background notification delivery, and signing.
- Xcode is absent on this Mac. Only Command Line Tools and the macOS SDK are installed. No iPhone SDK or simulator is available. An official App Store installation attempt stalled on its confirmation sheet; user action is pending.

The iOS app is not installed on an iPhone or distributed through TestFlight or the App Store.

## Scope

The implemented app covers the requested substitutions, independent day variants, flexible warm-ups, per-exercise notes, local storage, mixed cardio, drop sets, and MYO reps. It also includes ordered programs, reusable day templates, independent copies, day/program CSV sharing, additive history CSV import, editable exercises, rest timers, plate calculation, progression rules, graphs, history editing, and backup/restore.

Not included: Apple Watch support, Health integration, superset management, variant merging, schedule calendars, or equipment-specific inventory counts. The design specification contains additional proposals beyond the implemented app.
