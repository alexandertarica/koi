# AGENTS.md

How to work in this repository. Read this first, then `SPEC.md` (what Koi does)
and `DESIGN.md` (how it looks). Keep `HANDOFF.md` current as you go.

## The product

Koi is an iPhone app that turns habits, nutrition and exercise into one daily
**Balance** score, on a calm, watery visual language. It is a real product for
real users: every feature must work end to end, persist correctly, and survive
relaunches, time zones and empty states.

## Stack

- Swift 6, SwiftUI, iOS 26 (Liquid Glass where available, graceful fallback to
  iOS 18 materials). Xcode 26.
- SwiftData for persistence. One `ModelContainer`, shared with the widget
  extension through the App Group.
- WidgetKit + ActivityKit (widgets, Live Activity), App Intents (controls,
  widget buttons), HealthKit, EventKit, CloudKit (backup), CoreLocation (runs),
  Foundation Models (on-device Apple Intelligence, optional).
- Analytics: local event hooks only; nothing leaves the device.
- Backend: the existing HTTPS endpoints described in `SPEC.md` (Backend).
  The app never holds a model provider key.

## Identifiers

| | |
|---|---|
| App bundle ID | `com.alexandertarica.koi` |
| Widget extension | `com.alexandertarica.koi.widget` |
| App Group | `group.com.alexandertarica.koi` |
| iCloud container | `iCloud.com.alexandertarica.koi` |
| Version | 1.0 (1) |

## Architecture

```
Koi/
  App/            KoiApp, root navigation, app lifecycle
  Model/          SwiftData @Model types only. No UI, no networking.
  Engine/         Pure logic: BalanceEngine, StreakEngine, HabitRules,
                  WorkoutCoach, PlateMath, DateParsing. No SwiftUI, no I/O.
                  Fully unit tested.
  Services/       Side effects: HealthService, CalendarService, NotificationService,
                  EstimateClient, BackupService, Analytics, RunTracker, LiveActivities.
                  Each behind a protocol so it can be faked in tests and previews.
  Features/       One folder per area: Hub, Todo, Intake, Movement, Workout,
                  Cardio, Progress, Profile, Onboarding, Tour, SmartNote.
                  Each holds its views and a small @Observable model.
  DesignSystem/   KoiTheme (colors, type, spacing), KoiGlass, KoiFoldRow,
                  KoiPrimaryButton, KoiTile, KoiStat, KoiDial, GlassChip,
                  KoiBackground. Every screen builds from these.
  Resources/      Fonts, assets.
KoiWidget/        Widgets, Live Activity, controls.
KoiShared/        Code both targets need (shared model schema, App Group keys).
KoiTests/         Engine and model tests.
```

Rules:

- Views never compute scores or dates themselves; they ask the Engine.
- Services are injected (environment), never reached through singletons from
  inside views, except where Apple requires a shared instance (ActivityKit).
- One source of truth per fact. No duplicated state between screens.
- `@Observable` models, not `ObservableObject`.
- No force unwraps outside tests. No `print`. Use `Logger`.
- No dead code, no commented-out code, no TODOs left unexplained in
  `HANDOFF.md`.
- Every user-facing string is plain, calm, and short (see DESIGN.md, Voice).

## Secrets

- `Koi/Config/Secrets.plist` holds `KOI_API_BASE_URL` and `KOI_APP_TOKEN`.
  It is git-ignored. `Secrets.example.plist` is committed with placeholders.
- Never commit a key, token or personal data. Never log them.

## Testing

- Unit tests for everything in `Engine/` (scoring, streaks, habit rules,
  date parsing, workout suggestions, plate math) and for model persistence.
- Run the tests before every commit. A red test blocks the commit.
- Build and launch on the iPhone 17 Pro simulator and look at every screen you
  touched, in light and dark, with empty data and with a full week of data.
- A DEBUG-only launch argument `-koiDemo` seeds a believable week of data.

## Commits

- Small, focused commits with plain-English messages describing what changed
  for the user ("To-do: dates typed in the title set the due date").
- Commit working states often.

## Build order

Follow the phases in `HANDOFF.md`. Finish and verify a phase before starting
the next. If time runs short, a smaller set of features that fully works beats
a larger set that half works.
