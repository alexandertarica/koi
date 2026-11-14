# HANDOFF

Living status of the build. Update at the end of every phase: what's done,
what's partial, known issues, and the next step.

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Project, targets, identifiers, App Group, SwiftData container, design system, background | ✅ |
| 1 | Engine: Balance, streak + freezes, habit rules, date parsing (tests) | ✅ |
| 2 | Hub: dial, scrub, pillar lines, Today list, trend chip | ✅ |
| 3 | To-Do: habits + to-dos, list + matrix, new to-do, new habit, archive, auto-urgent | ✅ |
| 4 | Intake: dial, quiet rows, food log with AI, meals, supplements, edit mode | ✅ |
| 5 | Movement: dial, steps, Health sync | ✅ |
| 6 | Workout journal + workout mode + rest + summary + routines + Koi's pick | ✅ |
| 7 | Cardio: GPS run, treadmill, class, stats | ✅ |
| 8 | Progress + Profile (fold rows, body weight) | ✅ |
| 9 | Onboarding + tour | ✅ |
| 10 | Notifications + calendar sync + iCloud backup | ✅ |
| 11 | Widgets, Live Activity (log set from lock screen), Log-a-meal control | ✅ |
| 12 | Smart note, readiness, habit coach, trends, supersets, plate drawing, workout import | ✅ |
| 13 | Analytics, polish pass on every screen, empty states, demo data | ✅ |

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
- Hub design pass: replaced the compressed hero with the 470pt left-edge half
  dial, focus-weighted pillar bars and labels inside its curve. The score,
  trend chip and streak now overlay the dial; Profile and Progress open in
  place, greeting changes at 10pm, and Today shows an ivory expand control on
  its label line. Demo nutrition uses the tracked goal values and the sample
  history maintains a qualifying seven-day run. Added coverage for the seeded
  nutrition score and streak. The app builds and all 55 simulator tests pass.
  Captured the Hub on the iPhone 17 Pro simulator. A second simulator starts
  the comparison app process but continues to display SpringBoard, so the
  paired visual review remains incomplete.
- Design foundation pass: added the tonal background wash, tiled film grain,
  device-motion tilt with Reduce Motion support, halo shadow, stronger glass
  treatment, shared splash sequence, staggered intro reveal, and the haptic
  vocabulary for taps, selection, checks, success, dial sweep, and ring fill.
  Matched the Hub header and shared tab bar proportions, and wired the initial
  reveal cascade and interaction feedback through Hub, To-Do, Intake, and
  Movement. The app builds and all 55 simulator tests pass. Captured the Hub
  after launch; the paired simulator currently opens setup even when launched
  with demo mode, so paired review of feature screens remains incomplete.
- Phase 3: added persistent habit schedules/check-ins and to-dos with title date
  parsing, required matrix placement, optional due times, notes, edit/detail
  folds, list and draggable matrix views, pause/archive/restore, delayed task
  archiving, stale Someday review, and due-soon urgency with Undo. The Hub now
  respects habit schedules and task archives. Twenty-three simulator tests pass;
  build, launch, empty state, create flows, matrix and urgency undo were checked
  on the iPhone 17 Pro.
- Phase 4: added editable nutrient goals and types, calorie/nutrient scoring,
  manual daily adjustments, meal estimate and manual-entry flows, camera/library
  image selection, saved meal editing and deletion, supplement tracking, and
  nutrition event scoring in the Hub. Estimate requests use the injected service
  and the private configuration is conditionally copied into the app bundle.
  Twenty-eight simulator tests pass; the empty Intake screen, meal entry, saved
  meal state, and goal editor were reviewed on iPhone 17 Pro.
- Phase 5: added step and rolling workout scoring, configurable step and weekly
  training goals, persistent manual step adjustments and training marks, and
  HealthKit reads for daily steps and workouts behind an injected service.
  The Hub now derives its Exercise pillar from movement events. Thirty-one
  simulator tests pass; the empty Movement screen, step logging, training mark,
  and Hub score update were reviewed on iPhone 17 Pro.
- Phase 6: added the workout journal, configurable routines and planned days,
  rest-aware Koi picks, workout sessions with editable and warm-up sets, rest
  countdown, progression suggestions, lift history, summaries and one-tap
  logging of a recent matching workout. Completed workouts persist into the
  Movement score and survived an app relaunch. Thirty-four simulator tests pass;
  the empty journal, session logging, rest, summary and saved history were
  reviewed on iPhone 17 Pro.
- Phase 7: added outdoor run tracking with an injected Core Location service,
  route and mile split persistence, pace, resume/discard, and route detail maps.
  Treadmill sessions track time, distance and pace; class and other activities
  can be logged and repeated. Cardio totals, eight-week mileage, bests, activity
  counts and recent sessions feed Movement training credit. Thirty-seven
  simulator tests pass; Cardio empty state, treadmill start/discard, class entry
  and saved activity detail were reviewed on iPhone 17 Pro.
- Phase 8: added weekly and monthly Progress views with selected-day Balance,
  pillar detail and weekly averages. Profile now persists a name, focus, avatar,
  body weight history, nutrition goals and movement targets; Hub greeting and
  Balance weighting follow the saved profile. Forty simulator tests pass, and
  Progress and Profile flows were reviewed on iPhone 17 Pro.
- Phase 9: added a persistent seven-step first-launch setup with editable starter
  habits, focus, optional body details, goal targets, Health access, notification
  preference, and optional email fields. Completion saves the profile, goals,
  habits, and onboarding state before showing a replayable 12-step tour. Forty-three
  simulator tests pass; the welcome screen was reviewed on iPhone 17 Pro.
- Phase 10: added injected local-notification and EventKit services.
  Profile can request Calendar access and configure Smart, Once a day, or None;
  onboarding saves the selected settings. To-Do changes refresh habit and timed
  task reminders, and timed tasks create, update, or remove linked calendar
  events. Added a versioned archive for every shared SwiftData model and save it
  to Koi's private CloudKit database on app background; a fresh install is offered
  restore when a backup exists. Profile includes backup status, manual backup,
  restore confirmation, and automatic backup controls. Forty-six simulator tests
  pass, including archive round-trip and replacement coverage; Profile integration
  settings were reviewed on iPhone 17 Pro.
- Phase 11: added shared, date-aware Balance and habit snapshots in the App
  Group; small and medium Balance widgets; small, medium, and large interactive
  habit widgets; Home and Lock Screen quick-log widgets; Balance, pillars, and
  next-action Lock Screen widgets; a workout Live Activity with the current
  set, rest countdown, and a lock-screen Log set action; and a Control Center
  meal control that opens the camera on a supported device. Widget and Live
  Activity actions persist through the shared SwiftData container. Forty-seven
  simulator tests pass; WidgetKit registered the extension, the app launched on
  iPhone 17 Pro, and the meal composer deep link was reviewed.
- Phase 12: added the tab-bar Smart Note sheet with food estimate, water, habit,
  to-do, workout-set and planned-lift actions. Foundation Models classifies
  notes on device when available, with a deterministic parser as fallback.
  HealthKit now reads sleep, HRV and resting heart rate against recent
  baselines, preferring Apple Watch sources; low readiness keeps usual loads in
  workout progression. Sunday coaching supports easing a schedule, setting a
  minimum, graduating a habit, or stacking a habit, with a two-week snooze.
  Graduation is preserved in backups and historical Balance. Workout routines
  import from text or photos through the configured backend with per-lift set
  and rep targets. Workout mode supports alternating supersets with rest after
  the pair and per-side plate drawings for barbell lifts, including bar-weight
  selection and nearest-load guidance. Tests cover readiness bands, plate
  selection, coach thresholds, note parsing, imported routine persistence,
  superset alternation and graduation backup. The latest combined suite now
  passes all 54 simulator tests. iPhone 17 Pro review covered Smart Note,
  Movement, workout import, To-Do and Profile.
- Phase 13: added release-only TelemetryDeck initialization and an injected
  analytics provider. Events cover screen visits, onboarding and tour completion,
  notes, food estimation, habit and task completion, and workout starts, sets and
  completion. Signals contain event names and non-sensitive categories only.
  Added an opt-in `-koiDemo` launch argument that seeds a fresh store with a full
  week of fictional habits, meals, water, movement, Balance, tasks, workouts,
  a run and body-weight history; it leaves any store with existing profile,
  habit, food or workout data untouched. An in-memory test verifies the seven-day
  seed and fresh-store guard. Fixed the project configuration list so Xcode
  exposes the target Release settings; verified Release resolves without `DEBUG`
  and compiles. Debug app, widget, and test targets compile, and all 54 simulator
  tests pass. On a clean iPhone 17 Pro simulator, the `-koiDemo`
  launch and Hub, To-Do, Movement, Intake, Workout Journal, and Smart Note were
  reviewed with seeded data. A repeat test command after the project-file fix
  stalled before test execution; the 54-test pass preceded that project-only fix.

## Partial / known issues

- GPS authorization and route math are covered through the injected run-tracker
  test double; physical-device GPS accuracy still needs a device run.
- The guided tour is currently a sequence of app explanations; target cutouts,
  tab changes during the tour, and its hands-on Smart Note step remain deferred.
  Calendar and notification authorization/settings are implemented; physical
  notification delivery still needs device verification.
- CloudKit account availability and a live restore need verification on a device
  signed into an iCloud account. Calendar authorization and notification delivery
  also need device testing; simulator review covered their settings screens.
- The Balance and habit widget layouts and workout Live Activity still need a
  visual pass on a physical iPhone; simulator checks covered extension
  registration and app routing. Control Center availability also depends on
  iOS presenting the registered control.
- Health readiness needs enough HealthKit sleep and recovery samples; the
  simulator has none. The workout-import endpoint and photo flow still need a
  configured-network device check. CloudKit restore, GPS accuracy, physical
  notification delivery, widgets and Control Center actions also require device
  verification.
- The `-koiDemo` full-week seed is part of Phase 13, so Phase 3 was visually
  checked with empty data and in-session task entry.
- Simulator target is iOS 26.5. The widget and shared schema framework retain an
  iOS 18 deployment target.
- The final visual review covered seeded data in the app's water theme. Empty
  state review was completed in earlier phases; this pass did not repeat every
  screen in both appearances. The root currently requests light system
  appearance for the intended glass and status-bar treatment.
- The second simulator opens setup rather than the seeded dashboard when
  launched with demo mode, so paired screenshots of feature screens remain
  unavailable. Direct screenshot capture works on both simulators.
- The haptic engine and intro reveal are wired into primary tab interactions;
  the remaining screen-specific interaction audit is still in progress.

## Next step

Continue the visual and interaction pass in order with To-Do, then Intake,
Movement, Progress/Profile, onboarding, and system integrations. Physical-device
verification remains for HealthKit, CloudKit, GPS accuracy, notification
delivery, widgets, Control Center actions, and configured-network workout
imports.
