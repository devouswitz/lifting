# Verification

Entries below are dated records. Earlier toolchain and distribution limitations describe the environment at that time; see the newest pass for current evidence.

Verified on October 18, 2026.

## Structural redesign (iPhone simulator)

- First iOS build and run: Xcode 27.1, iOS 27 simulator (iPhone 18 Pro Max), Debug, demo data. Every screen below was checked on iPhone in light and dark, not only in the Mac preview.
- Train: program row opens Programs; next-workout card starts and resumes; later days open a day screen. Make Next Workout from a day's menu moved Lower to the main card and wrapped the later days. The orphaned "+" menu and the Program/Templates switch were replaced by Programs rows, the day menu, and Start Empty Workout.
- Programs: native grouped list with load-by-tap, info button to the program, templates, New Program (checkmark template selection), New Template, Import from CSV. Program screen: numbered days with Next badge and swipe actions, Add Day, details, current-program state, duplicate, export, delete.
- Workout: Finish uses the prominent glass style; one column header; Warm-up and Working groups; inline note; Working and Rest tokens; Swap moved into the exercise menu; completed rows fill with the Completed color; solid floating rest capsule with ring. Keypad sheet is compact, names the set, and replaces the value on first key.
- Active workout appears in the iOS 26.1 tab bar accessory while minimized; earlier iOS versions keep a floating bar above the tab bar.
- Settings uses colored tile icons tied to the color roles; Plate Calculator is a pushed screen; Colors editor preview and per-appearance pickers checked in dark.
- Progress: program filter is a labelled toolbar menu; the create-exercise "+" was removed from Progress (exercise creation remains in every exercise picker); chart series use ten distinct colors.
- History month comparison shows value and change together; zero change reads "same".
- An independent review of the diff found nine issues, none crashing; eight were fixed: note keyboard now dismisses (scroll or keyboard Done), Colors saves on leaving the screen, the keypad accepts hardware keys and grows at accessibility sizes, Make Next Workout also loads that program, the rest ring keeps its scale across ±15 and reopening, Reorder's Done stays visible, and color data decoding drops unknown or malformed entries instead of rejecting a backup. Keypad entry (1, 2, 0 replacing 95) and the resulting set value were checked in the simulator.
- Custom set types (simulator): created Back-off (badge B, counts as working); long-pressed a workout quick-add button, swapped Drop for Back-off, and tapped it to add a B set copying the last working set. Core test covers save, uniqueness, counts-as changes updating prescriptions, live adds, volume, day and history CSV round trips, sync, deletion fallback, and older backups.
- Superset editor uses checkmark selection and rest steppers; a superset showed on the day screen and in the workout, and logging moved focus to the partner without the list jumping (the jump was a bug fixed in this pass). Programs > Exercises and its New Exercise row were checked.
- 61 core test cases, zero failures. Mac preview builds with Xcode's toolchain; the ManifestAPI workaround is no longer needed.
- Not verified: a physical iPhone, Dynamic Type at accessibility sizes, VoiceOver end to end, iOS 17-25 fallbacks on a device (they compile, but no older simulator runtime is installed).

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

## Pass of 2026-10-18 (requested fixes)

Checked on the iPhone 18 Pro Max simulator (iOS 27) with demo data; 63 core test cases, 0 failures.

- Finish: saving a workout started from a day screen returns to the Train cover.
- Program screen: the name is the large title and renames in place ("Starter" to "Starter Plus"); Details is now Notes. The day editor uses the same title.
- Programs Edit shows delete and reorder controls on day templates as well as programs; swiping a template shows Duplicate and a red Delete with confirmation.
- Skip Workout on the next day: confirmation names the following day; History shows the day as Skipped with every set unchecked; the calendar marks it with a dashed ring; it is not counted as a workout, in muscle totals, or as the Previous value.
- Move Later on the next day made the following day next; Move Earlier is disabled for the next day. Core test covers moves across the wrap.
- Calendar: the month list under the calendar is gone; tapping a day lists that day only. "Compared with September" opens Past Week, Month, 3 Months, Year; Past Week read "Oct 12–18 compared with Oct 5–11".
- Average volume by muscle per workout appears under the comparison with deltas and bars.
- Hide from Progress (long press on a record, or the exercise menu) removed Triceps pressdown from the chart, legend, picker, and records; Hidden exercises lists it with Show.

## Apple Health (2026-10-20)

Core tests (68 cases, 0 failures) cover matching a watch workout and summing a warm-up plus a strength workout; never saving over another source's workout, including one without calories; waiting before saving; deleting only Lifting's copy when a watch workout appears later; unlinking and relinking; skipped and old sessions; validation; health values left out of folder sync while a merge keeps each device's own; and CSV round trip.

Checked on the iPhone 18 Pro Max simulator (iOS 27) with ad hoc signing and the HealthKit entitlement:
- Turning on Add Calories showed the Health permission sheet for Active Energy, Workouts, and Heart Rate, then the data range step.
- A workout logged in Lifting from 4:51 to 4:51 PM matched a 4:46 to 4:53 PM workout entered in the Health app with 210 calories. History showed "210 kcal" on the log row and "210 kcal · Health" in the workout. Health still showed a single workout with its 210 calories.
- With Save Workouts on (test launch with `--health-save-delay 20`), a session at 5:05 PM with nothing else recorded was saved to Health as Traditional Strength Training from Lifting.
- A 5:04 to 5:07 PM workout with 150 calories was then entered in Health. On returning to Lifting, Health went from three workouts to two: Lifting deleted only its own copy, and both other workouts kept their calories (360 total). The session showed "150 kcal".
- The Mac preview builds with Apple Health excluded.

Watch-shaped workouts (2026-10-20). A test helper app saved workouts the way the Workout app does: a separate source, an Apple Watch device, per-minute active energy, and heart rate samples every 30 seconds. Health computed the workout totals from those samples. Times below are 5 PM local; every workout Lifting saved was read back from Health with its source.
- Lift, then run on the watch, in one Lifting session (5:25 to 5:29): the strength workout (120 kcal) and the run (90 kcal) both counted. The workout showed "210 kcal · 133 bpm average · Apple Watch" with a line for each. Lifting saved nothing.
- One watch workout left running across two Lifting sessions (Lower 5:30 to 5:32, Push 5:32 to 5:35), 60 kcal burned in the first and 140 in the second: Lower showed 60 kcal and Push 140 kcal. The earlier session kept its 210. Lifting saved nothing.
- The watch recorded only a run at the end of a 7-minute session: Lifting saved strength training from 5:36:32 to 5:42:20, ending where the run began. The run was untouched, and the session showed its 40 kcal.
- A session with only a Run was saved to Health as Running.
- Found and fixed during this pass: a watch workout ending within 10 minutes of the next session counted toward both. Each workout now counts once, split by when the energy was burned.

## Apple Watch check on real devices (not yet run)

No iPhone or Apple Watch was available while building this, so it has only been checked in the simulator. To check it on a real iPhone paired with an Apple Watch:

1. In Xcode, select your team under Signing & Capabilities (the HealthKit capability is already declared), choose the iPhone, and Run.
2. In Lifting, open Settings > Apple Health, turn on Add Calories from Apple Health, and allow Workouts, Active Energy, and Heart Rate. Leave Save Workouts off for the first lift.
3. Start a Traditional Strength Training workout on the watch, then start the day in Lifting. Lift as usual. End the watch workout, then tap Finish and Save Workout in Lifting.
4. In the Fitness app, check that the day shows one strength workout from the watch, with its calories and heart rate unchanged.
5. In Lifting, open History. The workout should show the watch's calories and average heart rate within a minute or two. If not, leave and reopen Lifting to make it check again.
6. Next time, turn on Save Workouts and lift without the watch. About 10 minutes after Finish (with Lifting open or reopened), Fitness should show one Lifting strength workout.
7. Lift with the watch again with Save Workouts still on. Fitness should show only the watch workout; Lifting should not add a second one.
8. Optional: on the watch, record strength training and then a separate run during one Lifting session. Lifting's workout detail should list both, and Fitness should show only the two watch workouts.

Report anything that differs, especially how many minutes the watch workout took to appear on the phone. The 10-minute wait before saving assumes the watch syncs within that time.



## Pass of 2026-10-23 (Torque 1.0 build 3)

83 core cases pass, with all earlier feature tests retained. Release simulator and arm64 archive builds pass. Tested isolated iPhone 17e/iOS 27 and iPad mini/iPadOS 27 sessions: template batch add, shared weights/warm-ups, live shadow weights/header sync, short/full swipe deletion, rep target range editing without replacing logged reps, default collapse/focus, pause/restart/save, and a delivered background reminder opening the matching workout. Tablet portrait/landscape picker search and multiselect passed. The largest accessibility text size exposed wrapping issues that were corrected. macOS logging/save and workout toolbar actions were verified.

The bundle/storage identities are unchanged. Exact reps, ranges, AMRAP, no-count, RPE/time/distance, all load rules, progression, warm-up presets, Drop/MYO/custom types, substitution scope, linking, templates, import/export, history, analytics, sync and Health remain available. The global template collection is under Programs > Saved Days.

Physical phone/Watch checks remain unrun. The native hold-and-drag UI could not be exercised with a sustained touch drag through the automation interface; the reorder mutation is tested, with Move Up/Down retained. TestFlight distribution status is recorded separately in the release deliverables.

Distribution IPA verification checks its signature, original bundle identity, exact build number, and HealthKit entitlements. A negative check rejects an export missing HealthKit. Fractional CSV pause boundaries have a regression test so timestamp precision cannot reject a valid paused workout on import.

## Pass of 2026-10-23 (Torque 1.0 build 4)

86 core test cases pass, retaining prior coverage. Added checks cover independent weight chains across templates, workouts, JSON and CSV; explicit anchors and progression; and advanced target edits preserving manually entered results. The old exercise-wide mutation API was removed after its callers were replaced. Optional per-set overrides retain compatibility with older saves and CSV files.

On the iPhone 17e simulator, the template and live chains were checked through native UI: 100/100/100, then 100/110/110, then 105/110/110. The first working set updates untouched percentage warm-ups. Save Weights to This Day and finishing retained 105/110/110, with explicit anchors only on the first two prescribed sets. Exact reps and ranges remained separate; increasing an exact target now clears its former equal ceiling. Program Duplicate/Delete remain in the row context menu and program details; deletion uses a centered confirmation with Cancel. Reorder is available when multiple programs exist, without competing swipe/edit backgrounds.

Number fields now use shared native controls with select-all on initial focus and full-row form hit areas. The single-value editor retains adjustments and supports decimals, clearing and paste. iPad mini portrait, dark appearance and maximum accessibility text were inspected. A wrapped fractional adjustment was fixed with two columns at accessibility sizes and a scaled value field. The native Mac preview accepted and saved 102.5, including inherited weights and rounded warm-ups.

Day and workout menus contain their own scope; exercise linking and configuration live on exercise menus. Exercise weights are derived, read-only summaries, including mixed-weight ranges. Native exercise drag/drop is shared by days and active workouts. Move Up/Down remains as accessibility actions on headers and was exercised in the simulator. Sustained touch dragging and physical iPhone/Watch behavior remain unverified through this automation interface. No claim of physical gesture verification is made.

The iOS simulator build and device Release archive pass. The exported distribution IPA passes signature, bundle identity, build number and HealthKit capability verification. All test data is isolated; user workout data was not changed. See the build 4 release report for distribution status and measured package sizes.
