# MathMitra — Maths Formula App

**Every maths formula. One app.** MathMitra is a free formula app for first-year
engineering students: **291 formulas**, each with its meaning, its symbols
explained, and a solved example — plus an AI Tutor, a photo scanner, and a
one-tap PDF of the whole book.

- **Web app:** https://yashx.xyz/MathMitra
- **Download page (Android APK + details):** https://yashx.xyz/MathMitra-app
- **Direct APK:** https://github.com/pimatrix/maths-formula-flutter/releases/download/apk-latest/app-release.apk

## What's inside

- **Formula library** — Basics (Algebra & Logarithms, Trigonometry,
  Differentiation, Integration & Limits) and Maths-I Units 1–5 (Matrices,
  Differential Calculus, Integral Calculus, Differential Equations,
  Complex Analysis). Search understands what you type — try `(a+b)²`.
- **AI Tutor** — step-by-step answers to any maths doubt, in simple English;
  open it from a formula page to ask about that formula.
  - 10 free questions per user per day on the app's own Gemini key — the
    number is **set by the admin** in the Admin Dashboard (IST-midnight reset).
  - **BYOK:** users can paste their own free Gemini API key. The key is
    stored **only on their device**, is never sent to our server or database,
    and the app calls Google directly with it — no daily limit.
- **Photo scan** — photograph a formula; AI drafts the entry for you.
- **PDF export** — the complete formula book as one clean PDF.
- **Accounts** — sign up to add your own formulas/categories; one account
  works on Android and the web. Includes analytics opt-out and full
  account deletion (Profile → Privacy & Account).
- **Themes** — light, dark, or system.
- **Admin dashboard** — live users, formula views, shares, devices, and
  the AI Tutor daily-limit setting.

## Pages & repos

| Piece | Where |
|---|---|
| This app (Flutter — web + Android) | this repo |
| Download / product page | `web/MathMitra-app/` in this repo, served at `yashx.xyz/MathMitra-app` |
| API backend (Next.js) | `pimatrix/maths-formula-sheet` |
| Terms / Privacy | `yashx.xyz/terms` · `yashx.xyz/privacy` |

The app is data-driven: formulas are bundled for instant/offline reads and
refreshed from the backend API; accounts and added formulas live in
Supabase (project `maths-formula-sheet`). User-added content syncs between
the app and the website automatically.

## Development

```bash
flutter pub get
flutter run            # device/emulator
flutter build web --base-href /MathMitra/   # web release build
```

### Deploy (web)

Vercel serves the committed `build/web` output (`vercel.json` maps the
`/MathMitra` path prefix). To update the live site: run the web build
above, commit the new `build/web`, and push — Vercel deploys automatically.

### Android APK

APKs are built by GitHub Actions (`.github/workflows/build-apk.yml`) and
published to the `apk-latest` release — the direct link above always
serves the newest build. (Local Gradle builds are not used.)

## Creator

**Yash Sharma** — https://www.yashx.xyz · MathMitra is free, with no ads.

## Version

**1.1.4** — Admin-settable AI Tutor daily limit · BYOK (bring your own
Gemini key) · download page · dark-theme fixes · analytics with opt-out ·
account deletion · dark/light/system themes.
