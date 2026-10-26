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


## Build 5 interaction polish

All 93 core cases pass, including the prior 86 regression cases. New cases cover keypad replacement, zero/decimal/clear input, category spelling and backup compatibility, equal elapsed calendar comparisons across daylight saving, short/leap months, future months, unknown rest days, unique workout days, and every quick-action assignment in backups.

Observed on isolated iPhone 17e and iPad mini simulators running iOS/iPadOS 27: restored keypad; first-digit replacement; valid dismissal saves; explicit Cancel discards; independent weight propagation and warm-up recalculation; template range editing from 8–10 to 9–12; direct set-type choices; custom equipment creation through nested navigation without premature parent saving; persistent shared quick-action assignments; No data for empty rest-day history; session state retained after app update and relaunch. Inspected portrait, landscape, light/dark appearance, and the largest Dynamic Type size. Fixed warm-up badge clipping found during review.

Both simulator and device Release builds pass. The exported build 5 IPA passes signature, identity, and HealthKit entitlement checks. No third-party dependencies or category-storage migration were introduced. Calendar summaries and day sets are computed once per render instead of repeatedly for each displayed statistic/day. Shared draft, load, set-type, and quick-action controls replace repeated implementations.

Physical-device gestures, VoiceOver speech, external iPad keyboards, older supported OS versions, live watch/Health sync, and notification delivery were not retested in this pass. Existing code and core coverage for these features remain. No Mac-specific release was prepared. See the interaction-polish release report for final TestFlight status and measured sizes.


## Build 6 Setform UI refinement

All 94 core cases pass, retaining the prior 93. The additional warm-up application test covers the built-in scheme without creating a library record, independent copies, completed live warm-ups, future-plan scope, backup validation, and atomic rejection of invalid input. No schema migration or third-party dependency was added.

Observed through native simulator UI on iPhone 17e and iPad mini running iOS/iPadOS 27: one direct Add Exercises control on an empty day; immediate single addition; ordered two-exercise batch addition; notes persisted after real keyboard entry; new exercise category selection returns to the uncreated parent draft, and Create adds once; template weights 100/110/110 with only two explicit anchors and matching warm-ups; changed MYO preview dismissal adds no sets; rep ranges retain both bounds across set navigation; Exact reps replaces one selected range without changing later ranges; accessible set reordering retains targets; advanced set details remain reachable.

A sustained simulator click exposed the parent row context menu intercepting rep holds. That menu was removed, child hold gestures received priority, and a sustained click then opened Rep Target directly while a tap opened the numeric range editor. Duplicate Set remains in the template badge chooser, deletion remains a swipe and accessibility action, and set reordering has its own mode. Live actual time/distance remain in Set Details as well as accessibility actions.

Live keypad navigation saved actual reps 10 and 12 while keeping targets 8–12 and 9–15 and all completion markers empty. App updates and relaunch retained the test days, notes, weights, exercise order and active session in isolated data directories. iPad portrait, landscape, dark appearance and maximum text size were inspected; numeric value scaling at accessibility sizes was corrected. Physical touch dragging, VoiceOver speech, external keyboards, older OS versions, Health/watch integration and notification delivery were not retested. Existing core coverage and integration code remain.

Existing editor dismissal and explicit creation/batch confirmation share DraftEditor. Saved-plan editing reuses the main exercise card instead of a second set table. Unchanged mutations skip validation, disk writes and activity/sync scheduling. No runtime speed claim is made without a benchmark. Bundle identity, local storage and sync paths remain unchanged; the installed name is Setform. See the release report for signing, package sizes and final TestFlight availability.

## Build 7 mechanics pass (October 25, 2026)

104 core test cases, zero failures; 10 new cases cover AMRAP targets and progression, Drop and MYO setup resolution, set conversion, the missed-mini-set rule and its undo, body weight volume and sync, signed and duration keypad entry, equipment families and slot swaps, collapse re-arming, and assisted-load CSV round trips. The iOS simulator Debug build and an unsigned Release device archive (build 7) pass.

Observed on the iPhone 17 simulator (iOS 27) through XCUITest driving the installed app with showcase data:
- Keypad: confirming reps with the checkmark completed the set and started rest; Next Set logged W1 and W2 in turn; four working sets entered through Next Set completed, and Bench press collapsed only after the keypad closed.
- Auto-collapse: a finished exercise collapsed; on the next exercise, a set changed to Failure and another removed with a full swipe still collapsed when the rest were checked; reopening a finished exercise kept it open.
- Rest: holding the rest bar's step buttons offered 5 seconds to 1 minute and 30 seconds applied; the rest token opened the m:ss keypad with presets and 2, 0, 0 read 2:00.
- Equipment: the menu listed Barbell with new versions; choosing one swapped the exercise for today, kept completed sets on the original, and showed an empty weight rather than 0. The day editor swapped a slot to Dumbbell row.
- MYO from the set badge turned set 3 into a 15+ activation with four 0:20 mini-sets; the Drop button added a drop in one tap; holding it offered Drop Setup and button choices.
- Bodyweight: Dip took +25 on one set, showing BW for the others; Progress > Body Weight logged 180 lb.
- Warm-up badge and percentage now share one compact cell.

An independent review of the diff found eight issues; all were fixed with regression tests (assisted loads in CSV import, undoing a missed mini-set, body weight on synced or imported workouts, drop conversion keeping an entered load, legacy MYO quick-add choices, AMRAP copies starting empty, the ± key replacing the value, and AMRAP misses counting toward deloads). Sync now keeps record kinds it does not recognize instead of rejecting the merge; devices on build 6 or earlier still reject weigh-in records, so update every device.

Release: the unsigned archive was signed locally with `Resources/Lifting.entitlements`, exported for App Store Connect with automatic signing on team VFT92SUD4D, passed `scripts/verify-ipa.py --build 7` (signature, identity, HealthKit), and was uploaded to App Store Connect on October 25, 2026.

Not verified: a physical iPhone, VoiceOver, accessibility text sizes, older iOS runtimes, and iPad.

## Build 8 (October 25, 2026)

110 core test cases, zero failures. New cases cover warm-up and missed-target rest (including supersets and the MYO exemption), ordering exercises as logged (never inside a superset), rep targets following down, failure goals that keep their range, Save Changes to Plan, collapsed mid-workout adds, and warm-up volume.

Observed on the iPhone 17 simulator (iOS 27) through real touch paths:
- Hold-and-drag reorder: three drags in a row moved cards correctly, including after a reorder and for an exercise added mid-workout; a header tap still collapses and expands. The previous system drag and drop failed intermittently in the same session, which matched the reported bug.
- Exercise picker: two exercises ticked (numbered 1, 2) and added in that order with the checkmark; the second arrived collapsed.
- Rep target keypad: set 1 changed from 8–12 to 10–15 and sets 2 and 3 followed.
- Rest: Bench press shows Rest 3:00 and Warm-up 1:00; a warm-up started a 1:00 rest; at zero the bar turned solid with Rest done and Done.
- Order as logged: checking Bench press's first warm-up moved it up behind Cable curl.
- Finish from a day page returned to the main Train screen. Day pages now open by a fixed day, and finishing clears the Train path.

Found and fixed during testing: the simulator's notification service stalled, and because rest alerts were scheduled synchronously on the main thread, logging a set froze the app. Rest alerts now run on a background queue with a generation check. An independent review found ten issues in the build 8 changes; all were fixed except one kept by design (Save Changes to Plan keeps a MYO cluster shortened by a miss).

Not verified: a physical iPhone (gestures, haptics, scrolling while a card is lifted near the screen edge), VoiceOver, accessibility text sizes, and iPad.

## Build 9 (October 25, 2026)

110 core test cases, zero failures.

Observed on the iPhone 17 simulator (iOS 27) through real touch paths, in the Push day editor with Bench press expanded:
- Scrolling: a vertical swipe that starts on a set row scrolls the page. The row's swipe-to-delete drag had high priority and captured vertical drags; it now runs alongside the scroll view and the first direction decides.
- Set reordering: holding the 50% warm-up badge and dragging it below working set 1 moved it there, and dragging it back restored the order. Holding a badge without moving opened Set Details; a tap opened the Set Type list. The first attempt failed because the badge's button gesture outranked a drag attached outside it; the drag now sits on the badge beside its tap.
- Rep target keypad: Range shows Minimum, Maximum, and Exact. Typing 5 in Exact turned 6–8 into 5 for set 1, and later sets with the same target followed.
- The exercise menu no longer lists Add Warm-up or Reorder Sets.

Not verified: a physical iPhone, VoiceOver, accessibility text sizes, and iPad.

## Build 10 (October 25, 2026)

111 core test cases, zero failures.

Observed on the iPhone 17 simulator (iOS 27) through real touch paths:
- Scrolling: in the Push day editor, a swipe that started on a collapsed exercise header did not scroll, while one that started on a set row did. With the header's hold-to-drag turned off, the same swipe scrolled, so the cause was SwiftUI's LongPressGesture inside a scroll view (making it simultaneous, or delaying the drag, did not help). On iOS 18 and later the hold now uses UIKit's long press recognizer, which runs alongside scrolling; scrolling pauses only while a row is lifted. After the change: header swipes scroll, a header hold-and-drag moved Incline dumbbell press below Cable lateral raise and back without the page moving, a header tap still expands, a badge drag moved a warm-up into the working sets and back, and holding a badge without moving opened Set Details with no type menu.
- Live set rows are spaced 8 pt apart, as in the day editor (were 2 pt).
- Workout menu: Cancel Workout opens "Cancel this workout?" with Discard Workout and Keep Workout.
- Warm-ups: after applying Standard to Bench press from Apply Warm-up Preset, Overhead press's menu offered Apply Standard: 50%, 70%, 85%, and one tap took it from 3 sets to 6.
- Plan Settings names the off state None instead of Manual.
- Supersets move as a block. Found during testing: dragging Incline dumbbell press between Cable lateral raise and Triceps pressdown split their superset. Now a drag on either member lifts both, a drop on a member lands before or after the whole group, Move Up and Move Down step past a group, and members that drifted apart are gathered when the group moves; a new core test covers each case for days and the live workout. Observed: the same drag now put Incline press after the pair, and dragging Cable lateral raise to the top carried Triceps pressdown with it.

Not verified: a physical iPhone (scrolling and drag feel), VoiceOver, accessibility text sizes, iPad, and the iOS 17 fallback path.

## Build 11 (October 25, 2026)

111 core test cases, zero failures.

The warm-ups redesign approved from the mockup. One Warm-ups sheet replaces Apply Warm-up Preset, Save Warm-ups as Preset, Remove Warm-ups, and the old preset editor; warm-up sets get a trimmed details screen. The approved mockup also had a checkmark in the sheet's toolbar; it was left out because it duplicated the Apply button.

Observed on the iPhone 17 simulator (iOS 27):
- Bench press's menu in the Push day editor lists Plan Settings, Superset / Circuit, Warm-ups…, and Remove Exercise.
- Warm-ups… opened with Current, Standard, and New chips; Standard's rows showed 50/70/85% as 97.5, 135, and 165 lb against 195 lb working; Bench press was preselected.
- Selecting Overhead press changed the button to Apply to 2 Exercises; changing W3's reps to 3 on the keypad showed Save as New Preset; saving named the preset and selected its chip; applying gave Bench press W3 85% × 3.
- Holding the W3 badge opened the trimmed details (85% of working, 165 lb, 3 exact; rest, type, folded RPE/time/distance; Delete Set). Delete Set removed W3 with no error.
- Holding the orange Warm-up label opened the sheet with the last-applied preset selected.
- Settings > Warm-up Presets > New preset opened the sheet with a name field, one row, and Create Preset disabled until named.
- In a live workout, holding W1 opened the same trimmed details with 97.5 lb under 50%; Delete Set removed it with no error.

Not verified: a physical iPhone, VoiceOver, accessibility text sizes, iPad, and scrolling that starts on the Warm-up label.

## Build 12 (October 25, 2026)

111 core test cases, zero failures.

- The live Warm-ups sheet no longer has "Also save to the day". It did save to the day, but nothing on screen showed it, and Save Changes to Plan in the exercise menu already copies the live sets, warm-ups included, back to the day.
- Keypads center their value. The Clear button (and ± on signed values) shared the value's row and pushed it left; they now sit over equal side margins. Observed on the iPhone 17 simulator: the Percent of Working Set keypad shows 50 centered.

Not verified: a physical iPhone.

## Build 13 (October 25, 2026)

112 core test cases, zero failures. The new case covers light-day detection (a 60% deload is flagged, a normal dip is not), rep records (only counts that add information), weekly volume buckets (empty weeks kept, totals match the muscle summary), and the 7-day body-weight average.

The Progress redesign, kept in the existing layout. Observed on the iPhone 17 simulator (iOS 27) with showcase data, which now includes 16 weeks of weigh-ins:
- Exercises: "4 of 6 lifts" charts Leg curl, Squat, Bench press, and Overhead press, with Calf raise and Leg press available but off. End labels 265, 190, 110, and 100 sit at their lines, the close pair nudged apart. Tapping Leg curl in the legend hid it and left the other three colors unchanged. Bench and Squat 5/3/1 deload sessions show as hollow rings off their lines.
- Records: Deadlift reads "195 lb × 5, Best 305 lb × 3"; current records read "★ Record" instead of repeating the number.
- Bench press detail: the Bench track's two 110 lb deloads are off the line, and Latest/Best/Change read 180/180/+25 (previously 110/180/−45). Volume shows vertical bars with the light days faded. Rep records show only counts that add information.
- Muscles: average sets a week as rows with the previous period's mark (1M: Legs 27.8, before 23.8). The first attempt compared against a period that was mostly before the showcase history began and read "before 6.5"; previous periods now count only weeks with history and are dropped under two weeks. Volume opens on the last full week (116k lb, up 15%), with a 69k weekly average that leaves out the week in progress; an earlier attempt opened on today's empty week and read "0 lb, down 100%".
- Body Weight: 181.6 lb, 7-day average 181.4 lb, down 0.2 lb a week, with weigh-ins and the average line for 1M and All.

Not verified: a physical iPhone, dark mode on device, VoiceOver, accessibility text sizes, and iPad.

## Build 14 (October 26, 2026)

112 core test cases, zero failures. The showcase test now checks that run pace gets quicker over the weeks and that weekly cardio distance adds up to the logged distance.

- Distance unit: Settings > Distance Unit (km / mi), independent of the weight unit, following the region until set (miles on the US simulator). Distances stay stored in meters; the workout column, keypad, set details, history, summaries, and Progress all read and type in the chosen unit. Switching to km in the simulator changed the Run detail from 4.97 mi and 8:50 /mi to 8 km and 5:29 /km at once.
- Pace: a new metric for cardio, in minutes per km or mile, drawn with faster higher. Best is the fastest session, and change reads −0:36 /mi for the showcase runs.
- Progress > Cardio: weekly or monthly time or distance bars with the average and the week in progress left out of it, chips for All cardio, Run, Row, and Bike, and each exercise's latest session (4.97 mi · 43:52, 8:50 /mi) with totals. A cardio exercise's screen opens on distance, drawn as bars per session.
- Exercise screens color their tracks from the first color (Run was pink, taken from its position across the whole app).
- Showcase data gains 16 weeks of Sunday runs and conditioning every other Wednesday; the program's next day is unchanged.

Not verified: a physical iPhone, logging a new cardio set in miles on device, VoiceOver, and iPad.
