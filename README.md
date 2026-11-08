# Maths Formula Sheet — Flutter App

One codebase for the website + Android app of the Maths Formula Sheet
(live at https://yashx.xyz/math-formula-sheet-m1).

- Read side: all formulas bundled for offline use; fresh data cached from the
  website API when online.
- Login/Signup use the SAME Supabase accounts as the website.
- Add Formula (with AI photo scan), Add Class/Category, Add Syllabus,
  My Formulas (edit/delete) and the Admin Dashboard all work through the
  website's API — data stays shared.

## Deploy (web)

Vercel serves the committed `build/web` output as a static site
(`vercel.json` maps the `/math-formula-sheet-m1` path prefix).

To update: `flutter build web --base-href /math-formula-sheet-m1/`,
commit the new `build/web`, push.

## Run locally

`flutter run -d chrome` or `flutter run -d web-server`.
