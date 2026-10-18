# Lifting: UI Design Specification

## 0. Design read and flags

**What success looks like.** Logging a set should take one tap when the plan is followed and three taps when it isn't. All customization lives in editors, never on the workout screen. The workout screen has a fixed layout, and only a few column toggles change it. This is how "simple" and "deeply customizable" fit together.

**Variants are the structural core.** A *Variant* is an independent track for an exercise. It has its own prescription, progression, notes and graphs. Every routine slot points to one variant. When an exercise is added to a day, the editor asks whether to share an existing track or create a new one. The default is a new variant labeled with the day name ("Upper"). Most of the requirements depend on this choice. Logged sets must store `exerciseID`, `variantID` and `slotID` so that renames and substitutions never rewrite history.

**Flags you may not have considered:**
1. **Data loss risk.** With no accounts and no iCloud, deleting the app deletes all data. Settings shows "Last backup: 34 days ago" as plain information, plus an optional monthly reminder that is off by default. This is the only safety net.
2. **Import: I recommend Replace only, not Merge.** Merging two divergent histories that both contain variants and substitutions is where bugs and duplicate tracks come from. Replace is safe if the app writes an automatic backup of the current data before importing. I hold this view firmly. Merge can be added later if you need it.
3. **Today-only substitutes still need a track.** A temporary substitute logs into that exercise's variant for the same day label, and creates that variant silently if it doesn't exist. This can produce small variants that clutter the list, so Progress lets you merge variants.
4. **Background rest alerts** use local notifications, which need a one-time permission prompt. Everything stays on device.
5. **"One tap" substitution** means one tap after opening the sheet when the scope is Today only. Choosing Future sessions adds one tap. That extra tap is deliberate, because it changes the plan.

---

## 1. Information architecture (4 tabs)

| Tab | SF Symbol | Contents |
|---|---|---|
| **Train** | `figure.strengthtraining.traditional` | Next session card, routines list, routine/day/slot editors, start empty workout |
| **History** | `calendar` | Sessions by month, session detail (editable), session notes |
| **Progress** | `chart.xyaxis.line` | Exercise list (the exercise library), exercise detail with graphs, variants, notes, PRs, create/edit custom exercises |
| **Settings** | `gearshape` | Units, increments, plates and bars, rest, display, appearance, data (backup) |

**Active workout.** The workout opens as a full-screen cover on iOS and as a sheet on macOS. It can be minimized to a 56 pt bar pinned above the tab bar, which shows "Upper A · 42:10 · Rest 1:12". Tapping the bar restores the workout. Only one workout can be active at a time.

**Train tab layout, top to bottom:**
1. Active workout bar, if one exists.
2. Next-up card: day name in Title2, routine name and exercise count in Subheadline, and a full-width **Start** button in the accent color. A "Choose another day" menu sits below it.
3. A **Routines** section. Each row shows the name and "4 days · Rotation". The `+` toolbar button creates a routine.
4. A secondary **Start empty workout** button.

---

## 2. Workout screen

### Frame
- **Toolbar, leading:** `chevron.down` (Minimize).
- **Toolbar, title:** day name in Headline, with elapsed time below in Caption, monospaced digits.
- **Toolbar, trailing:** `square.and.pencil` (session note), then a **Finish** text button in the accent color, semibold.
- **Body:** a `ScrollView` with a `LazyVStack` of exercise cards. Spacing is 12, with 16 horizontal padding. The list ends with an **Add exercise** button (bordered, full width).
- **Rest bar:** overlaid at the bottom safe area, shown only while a rest timer runs.

### Exercise card
Surface color, 14 pt continuous corner radius, 16 padding. Light theme adds a 0.5 pt separator border. Dark theme has no border.

```
┌──────────────────────────────────────────────┐
│ Cable Lateral Raise  [Upper]  [⟳ Substitute] ⋯│  Title3 semibold, chip, bordered small button, menu
│ 3 × 12-15 · RPE 8 · Rest 1:30                │  Subheadline secondary
│ ↗ 25 lb  Hit 15,15,15 last time   Use 20     │  progression chip (only if a rule fired)
│ 📌 Seat 4, lean 15°, pinky up                │  recurring note, 2 lines max, tap to expand
│ SET  PREVIOUS   LB    REPS  RPE   ✓          │  Caption2 semibold tertiary, uppercase
│ W1   --         50%·10  10        ○          │  warm-up row, surface2 tint
│ 1    20 × 15    25     12         ○          │
│ 2    20 × 15    [25]   [12]       ○          │  bracket = placeholder (tertiary)
│ + Add set                    Note for today  │
└──────────────────────────────────────────────┘
```

**Controls:**
- **Substitute button:** always visible as `arrow.triangle.2.circlepath` plus the label "Substitute". If the header wraps (narrow width or large Dynamic Type), it collapses to the icon alone, with accessibility label "Substitute Cable Lateral Raise".
- **Overflow menu** (`ellipsis.circle`): History, Plate calculator, Add warm-up set, Edit prescription (Today only / Routine), Superset with…, Move up/down, Remove from today.
- **Set check button:** 44×44 hit area, drawn as a 28 pt `circle`.
  - Tapping it **commits the placeholder values** when fields are empty. This is the tap-fast path.
  - On commit: the symbol becomes `checkmark.circle.fill` in the accent color, the row background becomes accent at 10% opacity, the app plays a light haptic, and the rest timer starts.
  - Tapping again un-completes the set.
- **Previous cell:** tapping it copies the previous set's values into the row.
- **Set number:** long-press opens a menu with Warm-up, Working, Drop set and Failure. Drop sets show "D", failure sets show "F".
- **Swipe left** on a row deletes it.
- **Placeholders:** the weight comes from the progression suggestion, otherwise the last session, otherwise the target. The reps come from the top of the target range if the last session hit it, otherwise from the last session.
- **When the last set of a card is completed,** the next card scrolls to the top. With Reduce Motion on, it moves without animation.
- **Card complete indicator:** a `checkmark.circle.fill` appears before the name. Cards never auto-collapse.
- **Supersets:** grouped cards get a 3 pt accent bar on the left edge and a Caption label "Superset A". Rest starts after the last exercise in the group.
- **Notes:**
  - The recurring note line uses `pin.fill`.
  - "Note for today" expands an inline multiline field. The note is saved as a dated note on this exercise and variant for this session.

**Columns by exercise kind.** Columns are derived from the kind and are never configured on the workout screen.

| Kind | Columns |
|---|---|
| Weight × reps | LB/KG, REPS, (RPE) |
| Bodyweight | +LB (optional added weight), REPS, (RPE) |
| Assisted | −LB, REPS |
| Timed hold | TIME, (LB), (RPE) |
| Cardio, steady | TIME, DIST, (RPE); pace computed under the row in Caption |
| Intervals | REP, TARGET, TIME, DIST, (RPE) |

The RPE column is shown globally via Settings > Display, and can also be turned on per variant.

### Warm-up rows
- **Label and styling:** W1, W2 and so on, with a surface2 background and secondary text.
- **Load cell format:**
  - `50% · 95` when a working weight is known.
  - `50%` with a Caption hint "needs working weight" when it isn't.
  - `95` for an absolute weight, `Bar` for an empty bar, or blank.
- **Optional fields:** reps, duration and RPE are each optional. Any field left blank is hidden in that row.
- **Rounding:** percent loads round to the equipment increment, rounding down.

### Numeric keypad (bottom sheet, cross-platform)
- **Height:** detent of about 320 pt; no system keyboard.
- **Top line:** the context ("Weight · Set 2") in Subheadline, with the value in Large Title using monospaced digits.
- **Step row:** −5, −2.5, +2.5, +5, using the equipment increment setting.
  - Reps fields use −1 and +1.
  - Warm-up load fields replace the steps with a segmented control: `%` | `LB` | `Bar`.
- **Grid:** 3×4 with digits, "." and `delete.left`.
- **Right column:** **Next** (accent; moves weight → reps → RPE → next set), **Done**, and `scalemass` for the plate calculator.
- **Duration fields:** entered as digits and right-filled into m:ss.

### Rest bar
- **Size and style:** 56 pt tall, surface color, top separator, with a linear progress bar along the top edge in the accent color.
- **Contents:** `1:42` in Title3 monospaced, then **−15**, **+15** and **Skip** as bordered small buttons.
- **At zero:** a success haptic, an optional sound, and a local notification if the app is in the background.
- **Durations:** the rest length comes from the variant (working rest or warm-up rest). Intervals use the interval rest.

### Interval cardio
- **Header:** the plan in the card header ("8 × 100 m · Rest 1:30").
- **Interval timer strip** above the rows:
  - A large monospaced timer.
  - **Start** (accent), then **Lap** while running.
  - Each lap fills TIME in the next open row, checks the row, and starts the rest countdown.
  - Rows can also be edited manually.

### Plate calculator (sheet)
- **Inputs:** target weight field and a bar picker (from inventory).
- **Bar diagram:** a horizontal bar drawn with SwiftUI shapes. Plates are rounded rectangles with height proportional to plate size and the plate weight on top. Plates use neutral fills, not color-coded, with weights written on them.
- **Text output:** "Per side: 45, 25, 5".
- **Remainder:** shown as an error label if the target can't be loaded exactly.

### Finish
- **Summary sheet:** duration, sets, volume, PRs (listed with `trophy`), and a session note field.
- **Buttons:** **Save** (accent) and **Discard workout** (destructive, with confirmation).
- **Incomplete sets prompt:** "3 sets not completed", with the options **Save as skipped** and **Go back**.

---

## 3. Routine and variant editor

**Routine screen** (Train > routine):
- **Name field.**
- **Schedule:** segmented control with Rotation | Weekdays. Weekdays shows seven toggle chips (S M T W T F S) per day.
- **Days:** a reorderable list with rows like "Upper A · 6 exercises". Includes **Add day**, plus **Duplicate** and **Delete** via swipe or context menu.

**Day screen:**
- Name field and a reorderable slot list.
- Each slot row: exercise name (Body), variant chip, and a summary in Subheadline secondary: "2W + 3 × 12-15 · Double progression".
- **Add exercise** opens the picker.
- Superset groups appear as indented brackets with a label.

**Slot editor.** Grouped Form. Each section collapses to a one-line summary until tapped.

1. **Exercise.** Shows the name; tapping it changes the exercise. The **Track** menu offers:
   - "Upper (this day only)"
   - "Shared with Push"
   - "New variant…"

   Footer: "Each variant keeps its own history, progression and graphs."
2. **Working sets.**
   - Sets stepper.
   - Reps: single value or range, via a toggle plus two fields.
   - Load: none, fixed weight, or % of e1RM.
   - RPE target; duration for timed kinds; distance and time for cardio.
   - A "Customize each set" toggle reveals per-set rows.
3. **Warm-ups.**
   - A list of steps. Each step has Load (None / % of working / Weight / Bar), Reps, Duration and RPE, all optional.
   - Presets menu: "Ramp: 50%×8, 70%×5, 85%×2", "Bar × 10", "None".
4. **Rest.** Working rest, warm-up rest, and an Auto-start toggle.
5. **Progression.** Segmented control with None | Double | Linear.
   - **Double:** increase by [increment] when every set hits the top of the range.
   - **Linear:** increase by [increment] after each session where all sets are completed.
   - **Both:** "Deload [10]% after [3] missed sessions".
   - **Behavior:** the rule only ever produces a suggestion chip and never changes weights silently.
6. **Notes.**
   - "All variants": the exercise's recurring note, with footer "Shown on every day this exercise appears".
   - "This variant": the variant's recurring note, with footer "Shown only on Upper".
   - The workout card shows both, with the exercise note first.
7. **Superset with.** Picker of other slots in the day.

**Exercise picker (sheet):**
- Search field, then filter chips for muscle, equipment and kind.
- A **Recent** section, then A to Z.
- When search has no match, the top row reads **Create "xyz"**.

**Create exercise:** name, kind, equipment (sets the increment and enables the plate calculator), primary muscles (used for substitution suggestions), and an optional unit override.

---

## 4. Substitution flow

**Sheet title:** "Substitute Cable Lateral Raise".

1. **Scope** segmented control pinned at the top, defaulting to **Today only**. The footer under it updates live:
   - Today only: "Upper A is unchanged."
   - Future sessions: "Replaces it in Upper A from now on. Push is not affected."
   - Future scope always applies to **this slot only**.
2. **Search field.**
3. **Sections:**
   - **Used here before** (earlier substitutes for this slot).
   - **Similar** (same primary muscle, with matching equipment ranked first).
   - **All exercises**.
   - **Create new**.
4. **Rows:** name, then equipment and last-performed date in Subheadline secondary.
5. **Tapping a row commits immediately** and closes the sheet. No confirmation step.

**After a Today only substitution:**
- The card is replaced in place.
- The header gets a Caption line: `arrow.left.arrow.right` "Instead of Cable Lateral Raise", with a **Revert** button.
- A toast at the bottom reads "Substituted for today" with **Undo**. It stays 5 s and is announced to VoiceOver.
- **Placeholders:** the sets, reps and rest come from the original slot. The weight comes from the substitute's last session on this day label, otherwise its last session anywhere, otherwise blank.
- **Logging:** sets go to the substitute's variant for this day label, which is auto-created if needed.

**After a Future sessions substitution:**
- Same in-place replacement, but the Caption reads "Replaces Cable Lateral Raise in Upper A".
- The routine slot now points to the substitute's variant, and the prescription and progression rule carry over.
- The old variant keeps its history. It is detached from the slot, not deleted.

**If sets were already logged on the original exercise:**
- Those sets stay on the original exercise.
- The original card collapses to a single row ("Cable Lateral Raise · 2 sets · substituted").
- The new card appears directly below it.

**History** labels substituted entries "Substitute for Cable Lateral Raise".

---

## 5. Progress

**List:**
- Search field and a sort menu (Recent, A to Z, Most logged).
- Each row:
  - Name.
  - Variant chips.
  - "Last: Oct 14".
  - A 60×24 sparkline of the primary metric in the accent color.
- Toolbar `+` creates an exercise.

**Exercise detail, top to bottom:**
1. **Header:** name in Title2, then kind and equipment in Subheadline. An **Edit** button covers name, kind, equipment and muscles.
2. **Variant filter:** a horizontal multi-select chip row (**All**, Upper, Push).
   - Selected chips are filled with the accent color.
   - A **Combine** toggle sits at the end of the row. Off draws one series per variant; on draws a single merged series.
3. **Metric menu:** Est. 1RM, Top weight, Volume, Total reps, Best reps, Duration, Distance, Pace. Only the metrics relevant to the exercise kind are listed.
4. **Range:** segmented control with 1M | 3M | 6M | 1Y | All.
5. **Chart** (Swift Charts), 220 pt tall, scaled with `@ScaledMetric`.
   - Uses `LineMark` and `PointMark`.
   - The first selected variant is drawn in the accent color, solid, with circle points.
   - Other variants are drawn in secondary text color with dash patterns `[4,3]` and `[1,3]` and square and triangle symbols, so variants never depend on color alone.
   - Tap or drag places a `RuleMark` with a value callout ("Oct 14 · 31.2 lb · Upper").
6. **Stats row,** three columns: Best, Latest, and Change over the range (signed, monospaced).
7. **PRs:** best weight at 1, 3, 5, 8, 10 and 12 reps, or best distance, time and pace for cardio. Filtered by the selected variants.
8. **Sessions:** dated rows showing sets ("25 × 15, 15, 14") and any dated note in secondary text. Tapping a row opens the session.
9. **Notes:** the recurring exercise note and per-variant notes, all editable.
10. **Variants:** rename, **Merge into…** (combines history), and delete (allowed only when the variant has no sessions).

**e1RM formula:** Epley by default, with Brzycki as an option in Settings.

---

## 6. History and Settings

**History:**
- Sections by month. Each row:
  - Date, then the day name in Headline.
  - Duration, sets and volume in Subheadline.
  - `note.text` if notes exist.
- **Session detail:** everything is editable, including sets, notes and date. **Delete session** is destructive and requires confirmation.

**Settings, grouped Form:**
- **Units:** weight (lb/kg) and distance (km/mi/m default).
- **Increments:** per equipment type (barbell 5, dumbbell 5, cable 2.5, machine 5).
- **Plates and bars:** inventory with a stepper count for each plate size, and a bar list.
- **Rest timer:** default rest, auto-start, sound, haptic, and background alerts.
- **Display:** RPE column, Previous column, keep screen awake.
- **Appearance:** System / Light / Dark.
- **Estimated 1RM formula.**
- **Data:**
  - **Export backup**: writes `Lifting-2026-10-18.json` via `fileExporter` or `ShareLink`.
  - **Export sets as CSV.**
  - **Import backup**: shows a preview ("142 sessions, 38 exercises, 3 routines"), then **Replace all data**, which writes an automatic backup of current data first.
  - "Last backup: date".
  - **Erase all data**: destructive, with a typed confirmation.
- **About:** version number and "Data is stored only on this device. No network access."

---

## 7. Visual system

### Typography
Use system text styles only, so Dynamic Type works everywhere. All numbers use `.monospacedDigit()`.

| Token | Style | Use |
|---|---|---|
| `screenTitle` | `.largeTitle.bold` | Tab roots |
| `sectionTitle` | `.title2.semibold` | Next-up card, detail headers |
| `cardTitle` | `.title3.semibold` | Exercise card names |
| `setValue` | `.body.semibold` mono | Set inputs |
| `body` | `.body` | Lists, forms |
| `meta` | `.subheadline` secondary | Prescriptions, summaries |
| `columnHeader` | `.caption2.semibold` tertiary, uppercase, tracking 0.5 | Set table headers |
| `chip` | `.caption.medium` | Variant chips |
| `timerLarge` | `.largeTitle` mono | Keypad display |
| `timer` | `.title3.semibold` mono | Rest bar |

### Spacing and shape
- **Spacing scale:** 4, 8, 12, 16, 24, 32. Screen margin 16. Card padding 16. Space between cards 12. Section gaps 24.
- **Corner radii (continuous):** cards 14, buttons 10, chips are capsules, sheets use the system default.
- **Minimum sizes:** 44×44 tap targets; set rows 48 pt tall at default Dynamic Type size.
- **Scaled metrics:** use `@ScaledMetric` for the check icon, chip padding, chart height and sparkline size.
- **No shadows.** Elevation comes only from the surface color.

### Palette

| Token | Light | Dark |
|---|---|---|
| `background` | `#F7F6F3` | `#121211` |
| `surface` | `#FFFFFF` | `#1C1C1A` |
| `surface2` (warm-up, chips) | `#EFEDE8` | `#262624` |
| `separator` | `#E2DFD8` | `#34332F` |
| `textPrimary` | `#1C1B19` | `#F2F1EC` |
| `textSecondary` | `#6B6862` | `#A8A59D` |
| `textTertiary` (placeholders) | `#9C988F` | `#75726B` |
| `accent` (deep green) | `#1E6F5C` | `#4CC9A6` |
| `onAccent` | `#FFFFFF` | `#0B1F1A` |
| `accentSoft` (completed row) | `#1E6F5C` @ 10% | `#4CC9A6` @ 14% |
| `destructive` | `#B42318` | `#FF6B5E` |
| `warning` | `#9A6700` | `#E0B341` |

Accent contrast:
- Light: about 5.6:1 on the background, and white on accent is about 6:1.
- Dark: about 9:1 on the background.

`textTertiary` is used only for placeholders and column headers. Never use it for values that have been entered. Define every token as an asset-free `Color` extension that switches on the color scheme, so it works on both iOS and macOS.

---

## 8. Accessibility

- **Accessibility text sizes:** when `dynamicTypeSize.isAccessibilitySize` is true, each set row reflows to two lines.
  - Line 1: set label and previous.
  - Line 2: input cells and the check button.
- **Header reflow:** the card header stacks the name, then the chip, then the buttons row. Substitute keeps its text label at these sizes.
- **VoiceOver, set rows:**
  - Each row is one combined element: "Set 2, 25 pounds, 12 reps, not completed".
  - Custom actions: Complete, Edit weight, Edit reps, Copy previous, Delete.
- **VoiceOver, charts:** provide `accessibilityChartDescriptor` and a "View as list" fallback in the session list.
- **Color independence:** completion is shown by the filled symbol and the row tint. Chart variants differ by dash and symbol.
- **Reduce Motion:** no auto-scroll animation and no spring on check; use a crossfade instead.
- **Reduce Transparency:** the toast uses solid `surface`.
- **Haptics:** for completing a set and the end of rest only. Wrap in `#if os(iOS)`.

---

## 9. Empty states and error labels

Each empty state is centered, with an SF Symbol at 32 pt in the secondary color, one line of text, and at most one button.

| Where | Text | Action |
|---|---|---|
| Train, no routines | No routines yet. | Create routine |
| History | No workouts logged. | none |
| Progress | Log a workout to see progress. | none |
| Chart, 1 point | One session logged. The graph needs two. | none |
| Chart, filter empty | No Push sessions in this range. | none |
| Day editor | No exercises in this day. | Add exercise |
| Picker search | No match for "xyz". | Create "xyz" |
| Substitute, Similar empty | No similar exercises. Search all exercises below. | none |

Error labels appear inline in Footnote, using the `destructive` color (or `warning` where marked), with `exclamationmark.circle` before the text.

- **Field validation:**
  - Enter a weight above 0.
  - Reps must be a whole number.
  - Minimum reps is above maximum.
  - Name already used.
- **Warm-up without a working weight:** Set a working weight to calculate warm-ups. *(warning)*
- **Plate calculator:** Can't load 47.5 lb exactly. Closest: 45 lb. *(warning)*
- **Import:**
  - This file is not a Lifting backup.
  - This backup is from a newer version of Lifting.
  - Import failed. Your data was not changed.
- **Export:** Could not save the backup file.
- **Delete variant:** This variant has 12 sessions. Merge it instead?
- **Notifications denied:** Rest alerts are off while Lifting is in the background. *(warning; button: Open Settings)*

---

## 10. Implementation notes for Codex

- **macOS:**
  - Use `.fullScreenCover` on iOS only. Use `.sheet` or a pushed view on macOS.
  - Guard `navigationBarTitleDisplayMode`, haptics and `UIApplication.isIdleTimerDisabled` with `#if os(iOS)`.
  - The custom keypad avoids keyboard-type differences between platforms.
  - On macOS, Return triggers Next and ⌘Return completes the set.
- **Test harness identifiers.** Use stable accessibility identifiers:
  - `workout.card.{slotIndex}`
  - `workout.card.{slotIndex}.substitute`
  - `workout.set.{slotIndex}.{setIndex}.complete`
  - `.weight` and `.reps` suffixes for set fields
  - `substitute.scope.today` and `substitute.scope.future`
  - `progress.variantChip.{label}`
  - `rest.skip`
- **Frameworks:** SwiftUI, Swift Charts, SwiftData or Core Data, UserNotifications and UniformTypeIdentifiers only. These are all system frameworks, with no packages, network code or analytics.

**Not verified:**
- The contrast ratios are hand-calculated and should be checked with Xcode's Accessibility Inspector.
- The 48 pt set row and 320 pt keypad heights should be tested on an iPhone SE-sized screen.