# Interface

## Workout

Program and Templates are separate views. A flat program picker loads each program at its saved next day. The next day shows a compact exercise, rep, and load preview with one Start Workout button. Other days show their names, exercise summaries, and a direct start control. Program management contains day ordering and template copying.

During a workout, each exercise is a collapsible panel. Opening one closes the others. Its warm-ups and working sets appear in separate tables with previous values, editable actual values, RPE, and completion checkboxes. Swap, rest, working load, Drop, MYO, and notes remain available within the expanded panel. Collapse after completion is opt-in.

## History

Log shows month-grouped workouts with actual exercise results. Calendar shows workout dates, selected-day results, and current versus previous month statistics. Workout detail uses read-only set tables; Edit opens the existing date, notes, and set controls. Exercise titles link directly to the relevant progress track.

## Progress

The first screen is a multi-exercise chart with exercise, metric, and range filters. Each day variant has its own series. Records contain only logged exercises. Exercise detail offers separate tracks, latest/best/change values, dated results, and notes. Scrubbing a chart displays actual values from a recorded session.

## Storage and identity

All state stays in local JSON. Exercise definitions and day variants have separate IDs. Substitutions retain a stable family so returning to an exercise resumes its original track. New day copies and imported routine copies get independent tracks. History CSV maintains import mappings across backups and incremental imports.

## Appearance

Neutral grouped surfaces, compact tables, and a single green action accent. No decorative headings or promotional copy. Native SwiftUI navigation, sheets, and controls support light and dark themes.
