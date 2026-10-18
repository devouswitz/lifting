# Lifting: Programs, Collapsible Exercises, CSV Sharing

## Terminology

These terms apply everywhere in the UI. The word "routine" is removed from the app.

| Term | Meaning | Where it lives |
|---|---|---|
| **Program** | An ordered list of Days with its own next-day position | Train, Programs list |
| **Day** | One session inside a Program, with its own prescriptions and history track | Inside a Program |
| **Template** | A reusable standalone day such as Upper, Lower or Push | Train, Templates section |
| **Workout** | A performed, logged session | History |

When a Template is added to a Program, it is copied and becomes a Day. After that the two are unrelated. "Last time" values, progression and suggested weights for a Day come only from that Day's own history track. Starting a Template on its own logs to the Template's track.

## Train tab

The tab keeps its current layout. The changes are a program row at the top, a Days section, and a toolbar menu.

1. **Program row** (14pt card): Shows the program name and a `chevron.up.chevron.down` icon, with "Day 3 of 5" in secondary text underneath. Tapping it opens a native Menu:
   - All programs, with a checkmark on the loaded one. Choosing one loads it immediately.
   - A divider, then "All Programs".
2. **Next workout card**: Unchanged, except the title reads "Next: Lower B". Start workout stays the primary green button. A trailing `ellipsis.circle` Menu offers "Skip to Day" (picker) and "Edit Day".
3. **Days section**: Header "Days", then compact rows in program order. Each row shows the day name and exercise count. The next day has a green "Next" capsule. Tapping a row opens the Day editor. The context menu offers Start, Set as Next, Edit, Duplicate, Save as Template, Export CSV and Delete.
4. **Templates section**: The existing Upper, Lower and Push cards, unchanged. Their context menu adds Add to Program (program picker), Duplicate and Export CSV.
5. **Toolbar trailing `plus` Menu**: New Program, New Template, Import CSV.

**No program loaded:** The program row reads "No program". The Next workout card is replaced by a card containing the single button "Load Program", which opens All Programs. Templates still work.

**Keeping place:** Every Program stores its own next-day index. Switching programs never resets it. Finishing a workout from a Day moves that Program's index forward, wrapping to Day 1 after the last day. Starting a day out of order with Start does not change the index. Set as Next does.

## All Programs (pushed from the menu)

- Inset grouped list. Each row shows the name, "5 days", and "Next: Push" in secondary text.
- The loaded program has a trailing checkmark. Other rows have a bordered "Load" button.
- Swipe actions: Duplicate, Delete.
- The toolbar has Edit (reorder programs) and a `plus` button.

## Program editor

- A name field.
- A "Days" list with drag handles always visible.
- At the bottom, an "Add Day" Menu with Blank Day and From Template. From Template opens a sheet picker and inserts a copy.
- Day rows support swipe to Duplicate or Delete.
- Tapping a row opens the Day editor. This is the existing template editor reused. When a Day came from a Template, it shows one secondary footer line: "Copied from Upper".
- The Day editor toolbar Menu adds Save as Template. This creates a new Template named after the Day. If the name already exists, it appends " 2".

## Live workout: collapsible exercises

**Header** (always visible, height matches the current name row):
- Leading `chevron.right`, rotating to `chevron.down` when expanded. 13pt semibold, secondary color.
- Exercise name and variant chip, both unchanged.
- Trailing: when collapsed, a progress summary. When the exercise is complete, add a green `checkmark.circle.fill`.
- The whole header is the tap target.

**Body** (expanded only): Set rows, working weight, Substitute, Drop, MYO and notes, all exactly as they are now. Nothing moves.

**Collapsed summary:**
- Incomplete: "2 of 4 sets".
- Complete: "4 sets · 185 × 8" (top set).
- Cardio: "20 min".
- If notes exist, add a small `text.alignleft` glyph so they are not forgotten.

The collapsed card is the same 14pt card at one row height.

**Auto-collapse:**
- When the last set of an exercise is checked, wait 0.5s, collapse it with the default spring, expand the next incomplete exercise, and scroll its header to the top.
- The rest timer still starts normally.
- If the user manually expands a completed exercise, it stays open for the rest of the session.
- Controlled by Settings > Workout > "Collapse Completed Exercises", on by default.

**Focus:**
- The header context menu offers Focus, Substitute, Move Up and Move Down.
- Focus collapses every other exercise. Checking the last set ends focus and auto-advance continues as normal.
- No banner or mode indicator. The collapsed cards make the state obvious.

**Workout toolbar `ellipsis` Menu:** Collapse All, Expand All.

**Initial state:** Opening a workout expands the first incomplete exercise and collapses the rest. Resuming a workout restores the last expanded state.

**Accessibility:** The header is a button labeled with the exercise name. Its value reads, for example, "Collapsed, 2 of 4 sets", and it responds to the activate action.

## CSV export

**Entry points:** The Export CSV item on a Day, Template or Program opens the system share sheet through ShareLink. File names:
- "Lower B.csv" for a Day or Template.
- "Hypertrophy Block.csv" for a Program.

**Format:** One row per prescribed set, with the first column `format`. Columns:

`format, kind, program, day_order, day, day_notes, exercise_order, exercise, variant, exercise_notes, set_order, set_type, reps_min, reps_max, weight, unit, percent, rpe, rest_sec, duration_min, distance, distance_unit, progression`

- `format` is `lifting-1`.
- `kind` is `program` or `day`.
- `set_type` is one of warmup, working, drop, myo, cardio.
- `percent` uses the same base the app already uses for percentage prescriptions.
- `progression` is a short token that Codex defines and documents in Settings > Data > CSV Format, for example `double:+5`.
- Notes repeat on each row and import reads the first non-empty value. Repeating them is simpler for spreadsheet editing than tracking which row holds them.
- Logged history is never exported to CSV.

## CSV import

**Entry points:** Train `plus` > Import CSV, and Settings > Data > Import CSV. Both use fileImporter.

**Import Preview sheet:**
- Title "Import Preview" with the file name in secondary text.
- Summary card, for example "Program · 5 days · 28 exercises · 112 sets".
- Expandable list of days, each with its exercises and set counts.
- A "Warnings" section, shown only when needed. Examples: "3 new exercises will be added" (with names) and "2 rows skipped" (with row numbers and reasons).
- Footer: "Adds new copies. Current programs, templates and history are not changed."
- Bottom buttons:
  - Program file: "Add" (bordered) and "Add and Load" (prominent).
  - Day file: "Add to Templates" only.

**Import rules:**
- Imports always create new items with fresh history tracks. They never merge with existing data.
- Name collisions get " 2" appended.
- A Day file imports as a Template.

## Settings > Data

- **"Sharing" section:** Import CSV, CSV Format.
- **"Backup" section:** Export Backup (JSON), Restore Backup (JSON). Both stay as they are.

The two sections stay separate so CSV sharing is never confused with a full backup.

## Where I'd push back

1. **Progress tab aggregation.** Independent history tracks per Day are right for suggested weights. The Progress tab should still chart an exercise across every track by default, with an optional program filter. Otherwise Bench Press progress splits across three Days and looks flat. I hold this view strongly.
2. **Auto-collapse trigger.** It should fire on the last set only, not on Drop or MYO additions. People often add a drop set after checking the last working set. I feel moderately strongly about this. A Drop or MYO added within the 0.5s delay should cancel the collapse.

## Unverified

- Whether the app's percentage base (e1RM or training max) is per exercise or per Day. This determines whether imported percentages transfer cleanly.
- The scroll-to-header behavior with the keyboard open while editing a set.
- How the Luna testers handle multi-day CSV files edited in Numbers, which may reorder or quote rows differently from export.