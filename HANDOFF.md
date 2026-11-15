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
  Live Activities and local notification descriptions. Analytics use
  `LocalAnalytics` and stay on device, with no external analytics dependency or
  app ID. Added the app-group SwiftData container and shared day/habit/task/food
  models.
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
  Captured the Hub on the iPhone 17 Pro simulator. Early paired attempts were
  blocked by first-run overlays; a later pass captured the Hub on both devices.
- Design foundation pass: added the tonal background wash, tiled film grain,
  device-motion tilt with Reduce Motion support, halo shadow, stronger glass
  treatment, shared splash sequence, staggered intro reveal, and the haptic
  vocabulary for taps, selection, checks, success, dial sweep, and ring fill.
  Matched the Hub header and shared tab bar proportions, and wired the initial
  reveal cascade and interaction feedback through Hub, To-Do, Intake, and
  Movement. The app builds and all 55 simulator tests pass. Captured the Hub
  after launch; paired screen captures were completed later for Hub, To-Do,
  Movement and Intake.
- Phase 3: added persistent habit schedules/check-ins and to-dos with title date
  parsing, required matrix placement, optional due times, notes, edit/detail
  folds, list and draggable matrix views, pause/archive/restore, delayed task
  archiving, stale Someday review, and due-soon urgency with Undo. The Hub now
  respects habit schedules and task archives. Twenty-three simulator tests pass;
  build, launch, empty state, create flows, matrix and urgency undo were checked
  on the iPhone 17 Pro.
- To-Do visual pass: aligned the screen header and add controls with the shared
  design, added today's completion count and a horizontal habit tick-ring strip,
  grouped open tasks into today, undated, and upcoming sections, and collapsed
  finished tasks behind a count row. Task and habit composers now open in place;
  archive rows include restore and delete actions. Added swipe-to-complete and
  swipe-to-reveal-delete behavior, plus placement analytics and completion
  feedback. Startup urgency now updates dated tasks without showing an undo
  toast; user-driven urgency changes retain the undo action. The screen header
  uses the full month name. The seeded To-Do screen was captured on two iPhone
  17 Pro simulators; all 62 simulator tests pass.
- Intake visual pass: changed the calorie indicator to a full-height left-edge
  semicircle with a calorie hero and segmented nutrient tracks and labels inside
  the curve. Added single-row nutrient expansion with preset additions, moved
  meal logging into the screen with an animated food ring and composer, and
  corrected AI meal logging analytics to capture estimate state before the save
  clears it. The seeded Intake screen and composer were captured; all 55
  simulator tests pass. The header now uses the full month name and shared
  section-label spacing/contrast; paired seeded captures were reviewed on two
  iPhone 17 Pro simulators, and the latest 62-test run passes.
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
- Movement visual pass: replaced the compact centered step meter with a
  left-edge semicircle, step hero and weekly workout segments inside the curve.
  Added an animated workout log ring whose selected state follows today's
  training record; retained Apple Health refresh and goal/journal entry points.
  The header now uses the full month name and shared section-label styling.
  Paired seeded Movement captures were reviewed on two iPhone 17 Pro
  simulators; all 62 simulator tests pass.
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
- Progress/Profile visual pass: made month and week periods navigable, added
  miniature Balance arcs in calendar cells, and restored historical period data.
  Progress and Profile now render directly inside the Hub's in-place panels
  without nested scroll/navigation containers. Replaced the weight slider with
  an accessible drag ruler, added same-as-last and history controls, and added a
  full trend/history sheet with deletion. DEBUG demo launches skip the splash so
  panel captures show content. Seeded Progress and Profile panels were captured;
  all 55 simulator tests pass.
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
  Group; small and medium Home Screen Balance widgets; dedicated circular
  Balance and rectangular Balance-with-pillars Lock Screen widgets; small,
  medium, and large interactive habit widgets; a dedicated three-ring habit
  widget; Home and Lock Screen quick-log widgets; a Lock Screen meal-camera
  widget; next-action Lock Screen widget; a workout Live Activity with the current
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
- Phase 13: added local analytics hooks and an injected
  analytics provider. Events cover screen visits, onboarding skip/completion and
  tour completion, pillar opens, notes, food estimation, habit and task
  completion/placement, workout routine creation, sets and completion, and
  cardio starts/logs. Signals contain event names and non-sensitive categories
  only.
  Added an opt-in `-koiDemo` launch argument that seeds a fresh store with a full
  week of fictional habits, meals, water, movement, Balance, tasks, workouts,
  a run and body-weight history; it leaves any store with existing profile,
  habit, food or workout data untouched. An in-memory test verifies the seven-day
  seed and fresh-store guard. Fixed the project configuration list so Xcode
  exposes the target Release settings; verified Release resolves without `DEBUG`
  and compiles. Debug app, widget, and test targets compile, and all 54 simulator
  tests pass. On a clean iPhone 17 Pro simulator, the `-koiDemo`
  launch and Hub, To-Do, Movement, Intake, Workout Journal, and Smart Note were
  reviewed with seeded data. Onboarding now spotlights app regions, selects the
  corresponding tab during the tour, and opens Smart Note after the hands-on
  swipe step. Skip and completion have separate analytics signals. A serial
  simulator run passes all 58 tests; a parallel test-runner session stalled
  while Xcode waited for its test worker to finish cleanup.
- System pass: added discoverable App Intents and Siri shortcuts for water,
  protein, meals, workouts, habits, and the meal camera, with shared-store
  persistence and tests. Smart Note now saves the original text as a durable,
  backed-up record before applying its detected action. A native share sheet
  sends saved notes to Apple Notes, and Profile lists the saved note history.
  The system build succeeds and all 58 simulator tests pass.
- Notifications pass: check-ins are planned as dated requests for the coming
  week, with Sunday week-review copy and a configurable 8am–8pm window. Habit
  reminders are one-shot, ten minutes ahead, and suppressed after a same-day
  check-in; timed to-do reminders route to To-Do. Notification taps select the
  related feature tab, and foreground alerts are suppressed. Onboarding and
  Profile enforce quiet hours. Added deterministic coverage for weekly copy,
  Sunday selection, time bounds, reminder timing and completion suppression.
  A clean serial iPhone 17 Pro simulator run passes all 60 tests. Earlier Xcode
  attempts stalled before XCTest launch; shutting down and booting the simulator
  cleared the runner state.
- Notification refresh pass: score-based catch-up, protein and step nudges now
  share one planner between the app launch refresh and To-Do. HealthKit movement
  updates replan notifications with the latest samples. Added deterministic
  coverage for the low-balance catch-up reminder. The latest serial simulator
  run passes all 63 tests.
- HealthKit pass: the service now observes step and workout changes and requests
  hourly background delivery, then posts a refresh event so Movement and
  readiness can reload current samples. This remains read-only. The app and
  widget build succeeds; the subsequent Reminders test run and final serial
  simulator run both passed all 61 tests with this observer code included.
  Health sample delivery and background scheduling need a device with Apple
  Health data.
- Reminders pass: Profile now has a separate Apple Reminders connection. Timed
  to-dos create, update and remove EventKit reminders independently from Apple
  Calendar events; both integration preferences and item identifiers survive
  backup restore. Added lifecycle and archive round-trip tests. The iPhone 17
  Pro simulator build succeeds and all 61 tests pass. EventKit authorization
  and delivery still need a device with a configured Reminders account.

## Partial / known issues

- GPS authorization and route math are covered through the injected run-tracker
  test double; physical-device GPS accuracy still needs a device run.
- The guided tour now spotlights app regions, changes the selected tab for each
  feature stop, and ends by opening Smart Note after its swipe gesture. Its
  target geometry has only compile-time verification so far; interactive
  spotlight positioning still needs device review. Calendar and notification
  authorization/settings are implemented; physical notification delivery still
  needs device verification.
- Optional beta and launch email addresses are validated and saved locally, but
  the app has no Koi-owned signup endpoint configured to submit them. No email
  address is sent; completing this feature needs a configured product endpoint.
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
- Paired demo captures now cover Hub, To-Do, Movement and Intake on two iPhone
  17 Pro simulators.
  Simulator preferences were used to dismiss the daily check-in and guided tour
  overlays for the captures. Each app has its own seed values, so the numerical
  scores and sample entries differ. Other screen pairs and paired empty-state
  captures are still outstanding.
- The haptic engine and intro reveal are wired into primary tab interactions.
  Workout start, lift selection, set logging, load/repetition changes and finish
  now provide feedback; outdoor and treadmill run start, finish and discard
  actions do as well. The screen-specific haptic and animation audit remains in
  progress, and physical feedback cannot be judged in Simulator.
- Progress and Profile were reviewed on the primary iPhone 17 Pro simulator;
  paired captures of their in-place panels remain outstanding because they
  require interactions that the available simulator command interface cannot
  send.
- Onboarding Back, Skip, Continue, focus/habit choices, and value steppers now
  provide tap, success or selection feedback; tour continuation and completion
  are also acknowledged. The first test launch exited before XCTest bootstrap;
  after rebooting the simulator, the retry passed all 63 tests.
- Progress period/day selection and Profile focus, goals, notifications,
  integrations, backup and navigation actions now acknowledge interactions.
  Two XCTest launches exited before bootstrapping; after rebooting the test
  simulator, the latest run passed all 63 tests. Nested profile panels still
  need paired visual review through interactive simulator controls.
- Widget bundle audit accounts for Balance, Balance and pillars, Home Balance,
  Habits, Habit Rings, Next Action, Quick Log, Meal Camera, the meal camera
  Control Widget, and workout Rest Live Activity. Siri/App Intents are present
  for water, protein, meals, workouts, habit completion/toggle, and meal camera;
  shared-store intent behavior is covered by persistence tests. Widget layouts
  and lock-screen actions still need physical-device review.
- Bundle IDs, app group, iCloud container, and 1.0 build 1 remain this app's
  configured identifiers. Paired empty-state visual captures remain outstanding;
  the current simulator review flow cannot clear the SwiftData onboarding state
  or interact with the first-launch overlay through available UI controls.

- Main tab visual pass: corrected demo launch seeding and sample values, added
  reliable `-koiTab` capture routing, aligned the shared shell and four tab
  layouts, and fixed the fifth-habit indexing crash. Captured the Hub, To-Do,
  Movement, and Intake screens on iPhone 17 Pro Simulator. Debug build succeeds
  and the full simulator suite passes all 64 tests.

- Food logging reliability pass: photo-only estimates are now enabled even
  when the meal description is blank. The estimate decoder accepts the
  confirmed nutrient payload when optional confidence and description metadata
  are absent. Added coverage for every returned nutrient and for saved, edited,
  and deleted meal totals flowing into Intake rows. The simulator suite passes
  all 65 tests. Live API use, library/camera interaction, widget routing, and
  Smart Note network save still need direct end-to-end simulator exercise.

- Food flow simulator pass: on one iPhone 17 Pro simulator, typed a meal and
  received all seven nutrient values from the live service, saved it, confirmed
  the Intake dial/rows and today's log updated, edited calories and confirmed
  the totals changed, then deleted it and confirmed the totals returned. Picked
  a library photo and confirmed preview/selection. Smart Note's food action
  estimated, saved once, and showed its success state. Simulator camera now
  explains that capture is unavailable and offers the photo picker. The live
  service and library-photo paths work; camera permission UI was not exercised
  on a physical device. The camera fallback is covered by an automated test.

- Onboarding quick-start pass: replaced the long first-launch setup with three
  screens (Welcome, Connect, Focus), optional name, optional Health/Calendar
  switches, and focus presets. Start saves balanced defaults (2,200 kcal, 140 g
  protein, 8,000 steps, four workouts/week), creates no starter habits, and
  offers the tour as a Hub chip. A clean iPhone 17 Pro install showed Welcome,
  Connect and the Apple Health permission request. Calendar permission, Focus,
  final Hub state, and tour chip remain to be checked interactively. A model
  persistence test covers empty setup, saved focus and defaults.

- Main-tab visual pass: compared Hub, To-Do, Movement and Intake on the same
  booted iPhone 17 Pro, switching between installed builds for captures. Corrected
  the Hub trend-chip contrast, removed secondary unit lines from Movement stats,
  and spaced Intake nutrient folds to the intended rhythm with full-width thin
  tracks. Hub score/pillars/streak/Today values and the To-Do rows matched the
  seeded data. All 67 simulator tests pass. One simulator was used sequentially;
  both appearances and empty-state captures remain to be checked.

- Sub-screen launch pass: direct debug launches displayed the workout journal,
  workout mode, routine builder, cardio/run view, new to-do, new habit, Smart
  Note, Profile, Progress and meal composer. The first captures revealed blank
  embedded task and habit forms: their nested navigation/scroll containers had
  no height inside the To-Do scroller. Embedded forms now render in intrinsic
  layouts with readable prompts; the simulator screenshots show the fields,
  choices and save controls. All 67 tests pass. Screenshots were reviewed, but
  simulator taps through workout logging, rest/PR feedback, run tracking, and
  the onboarding tour remain outstanding.

- Quick setup simulator pass: confirmed all three screens render on the iPhone
  17 Pro, with title-case Next/Start labels, and completed Start into the
  demo-free Hub. The optional “Show me around” chip opened the tour and Skip
  returned to Hub. Tapping Calendar prompted for full access; after allowing,
  its switch stayed on. The Health permission screen appeared during the earlier
  clean-install run and remained optional. All 67 simulator tests pass.

- Final four-tab visual pass: recaptured Hub, To-Do, Movement and Intake on the
  same booted iPhone 17 Pro using the seeded sample week. Header, tab bar,
  movement totals, Intake dial and nutrient values aligned. Raised the Intake
  nutrient tracks within their rows and restored the broader filled track and
  marker sizing. Debug build succeeds; all 67 simulator tests pass.

## Final validation (2026-11-14)

### Verified

- The latest Debug simulator test run passes all 67 tests. This includes
  estimate response decoding and meal persistence through save, edit, and
  delete.
- The Release app and widget build successfully. A clean install on the iPhone
  17 Pro simulator, launched with no arguments, displays the first onboarding
  screen and no demo data. The bundle is `com.alexandertarica.koi`, version
  1.0 (2); the app and widget retain Koi's App Group and iCloud container.
- Release compilation still emits two non-fatal Swift 6 sendability warnings:
  the onboarding connection-toggle setter and the routine photo-picker label.
- The Release executable contains no `-koiDemo`, `-koiScreen`, `-koiTab`, or
  `-koiShowMealComposer` routes. No external analytics package is configured.
  `LocalAnalytics` records event names and private parameters to on-device
  unified logging.
- A live text estimate returned all seven nutrients in the earlier simulator
  path, saved once, and updated Intake totals and Hub Balance. Meal save/edit/
  delete behavior is covered by model tests. The current composer screenshot
  shows the in-place scrollable layout without the old panel, clipping, or
  off-Hub tour chip. A Debug camera route screenshot confirms the friendly
  Simulator camera fallback and manual-entry option.
- Direct simulator screenshots reviewed the workout journal and mode, routine
  builder, run screen, new to-do and habit forms, Smart Note, Profile, Progress,
  and meal composer. The workout PR path now uses success feedback; the other
  dial, check-off, and save feedback paths remain wired.
- The simulator has Calendar and motion permissions revoked for denial-state
  coverage. The clean Release screenshot and screenshots of the updated food
  and camera-fallback views were inspected.

### Still unverified

- The CLI-only simulator control path cannot tap through onboarding, the photo
  picker, meal result/edit controls, task/habit save controls, permission
  toggles, or workout/run actions. The current clean Release run therefore
  stops visually at Welcome; prior Debug interaction runs reached the Hub and
  exercised the core task, habit, and typed-food paths.
- The rewritten photo-picker auto-estimate path has not been activated end to
  end. The earlier photo test selected and previewed a library image before the
  composer rewrite. A forced offline estimator response, denied-permission
  retry interaction, and the complete fresh-install path in Release have not
  been driven in this pass.
- A physical iPhone is still needed to verify camera capture, GPS accuracy,
  physical haptic strength/timing, HealthKit data and authorization behavior,
  notification delivery, CloudKit account/restore, widget placement/actions,
  Live Activity visibility/actions, and Control Center actions.
- HealthKit writes are not implemented, and a Koi-owned signup endpoint is not
  configured. Configured-network workout import has not been exercised in this
  final pass.

### Browser demo refresh (2026-11-14)

- Reworked the browser demo's Hub, To-Do, Movement and Intake visuals around the
  left-edge 180-degree dial: 72 value-aware ticks, weighted inner bars, bead and
  1.65-second draw-in; added thin Intake nutrient tracks, movement stats, habit
  initials/check rings, app-style tab icons and header controls. Removed the
  Hub's stray divider, shows “See progress” without week history, and hides AI
  confidence on manually entered meals. Demo plan requests use the `plan` task.
- Added `demo-api/` as a self-contained Vercel project root with the single
  `/api/demo-ai` endpoint. It calls OpenRouter server-side, returns the app's
  estimate fields or workout routines, accepts CORS only from GitHub Pages,
  and applies per-device (30/day) and global daily quotas in warm-instance
  memory. These quotas are best-effort across Vercel instances; durable global
  enforcement needs a shared counter service.
- The browser points to `https://koi-demo-api.vercel.app/api/demo-ai`. It will
  return a setup error until `OPENROUTER_API_KEY` is configured in that separate
  project. The model defaults to `openai/gpt-4o-mini`; it can be overridden by
  `OPENROUTER_MODEL`. The app repository does not specify the existing backend's
  model identifier, so exact model parity has not been confirmed.
- Static JavaScript syntax checks pass. The first unsigned test attempt crashed
  before test bootstrap because the app-group entitlement was absent; rerunning
  with ad-hoc simulator signing passes all 67 tests. The updated browser demo
  still needs live Pages visual review at phone size and the separate API project
  still needs creation/deployment and its key configured.

