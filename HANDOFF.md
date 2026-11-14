# HANDOFF

Living status of the build. Update at the end of every phase: what's done,
what's partial, known issues, and the next step.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Project, targets, identifiers, App Group, SwiftData container, design system, background | ✅ |
| 1 | Engine: Balance, streak + freezes, habit rules, date parsing (tests) | ✅ |
| 2 | Hub: dial, scrub, pillar lines, Today list, trend chip | ✅ |
| 3 | To-Do: habits + to-dos, list + matrix, new to-do, new habit, archive, auto-urgent | ☐ |
| 4 | Intake: dial, quiet rows, food log with AI, meals, supplements, edit mode | ☐ |
| 5 | Movement: dial, steps, Health sync | ☐ |
| 6 | Workout journal + workout mode + rest + summary + routines + Koi's pick | ☐ |
| 7 | Cardio: GPS run, treadmill, class, stats | ☐ |
| 8 | Progress + Profile (fold rows, body weight) | ☐ |
| 9 | Onboarding + tour | ☐ |
| 10 | Notifications + calendar sync + iCloud backup | ☐ |
| 11 | Widgets, Live Activity (log set from lock screen), Log-a-meal control | ☐ |
| 12 | Smart note, readiness, habit coach, trends, supersets, plate drawing, workout import | ☐ |
| 13 | Analytics, polish pass on every screen, empty states, demo data | ☐ |

## Done

- Phase 0: created the Xcode project with app, widget extension, shared schema
  framework and unit-test targets. Set bundle IDs, version/build, team, iOS
  deployment targets, App Group, HealthKit, iCloud, location background mode,
  Live Activities and local notification descriptions. Added the TelemetryDeck
  package and its release-only app ID, app-group SwiftData container and shared
  day/habit/task/food models.
- Phase 0: added the brand image catalog and fonts, water background, theme
  tokens, glass components and four-tab shell. The iPhone 17 Pro simulator build
  succeeded, the SwiftData persistence test passed, and the app launched for a
  visual check.
- Phase 1: added pure Balance weighting/capping, never-miss-twice and minimum
  habit credit, rolling counting-day streaks with two-bank freeze rules, and
  calendar-aware title date/time parsing. Fifteen engine tests cover thresholds,
  gaps, freeze earn/spend, graduated habits, invalid inputs and clock rollover.
  The simulator build and launch succeeded.
- Phase 2: added the animated 72-tick Balance dial, seven-day hold/slide review,
  pillar detail folds, streak/trend summaries and the two-item Today list with
  persistent task completion and habit check-ins. Eighteen simulator tests pass;
  the iPhone 17 Pro build and empty-state launch were visually checked.

## Partial / known issues

- Intake and Movement pillar values currently come from daily score records;
  Phases 4 and 5 add event-level food and activity data.
- To-Do, Movement and Intake remain placeholders pending their phases. The Hub's
  Profile and Progress sheets are previews; Phase 8 replaces them with full views.
- Simulator target is iOS 26.5. The widget and shared schema framework retain an
  iOS 18 deployment target.

## Next step

Phase 3: build To-Do habits/tasks, list/matrix, creation flows, archive and urgency.
