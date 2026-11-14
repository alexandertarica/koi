# HANDOFF

Living status of the build. Update at the end of every phase: what's done,
what's partial, known issues, and the next step.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Project, targets, identifiers, App Group, SwiftData container, design system, background | ✅ |
| 1 | Engine: Balance, streak + freezes, habit rules, date parsing (tests) | ☐ |
| 2 | Hub: dial, scrub, pillar lines, Today list, trend chip | ☐ |
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

## Partial / known issues

- The four tabs are foundation placeholders; feature behavior begins in Phase 1.
- Simulator target is iOS 26.5. The widget and shared schema framework retain an
  iOS 18 deployment target.

## Next step

Phase 1: implement and test Balance, streak/freezes, habit rules and date parsing.
