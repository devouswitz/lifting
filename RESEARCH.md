# UI references

Reviewed October 18, 2026. Claude Opus supplied the UI refinement specification in `DESIGN-REFINEMENT.md`; Codex implemented the native app.

- [Strong: templates](https://help.strongapp.io/article/105-about-templates). Reusable prescriptions remain separate from completed workouts. Adopted as Templates and logged history.
- [Hevy: gym routines](https://www.hevyapp.com/features/gym-routines/). Programs organize reusable training days. Adopted as ordered Programs with a next-day Start control and quick Load menu.
- [Hevy: building a workout program](https://help.hevyapp.com/hc/en-us/articles/34953606698903-Build-a-Workout-Program-Create-Organize-Routines). Folder and routine organization informed the program/day editor.
- [FitNotes: routines](https://www.fitnotesapp.com/routines/). A compact routine picker informed the day list and direct Start affordance.
- [Hevy: importing Strong data](https://help.hevyapp.com/hc/en-us/articles/35687878672663-Importing-Strong-Data-into-Hevy). Its documented history import excludes saved routines. Lifting therefore exports day/program prescriptions separately from logged-set history.

Leading exercise chevrons, manual expansion, and delayed completion collapse implement the requested focus behavior. Copying a template creates independent variant IDs rather than shared prescriptions. These are product decisions for this app, not claims about competitors' internal data models.
