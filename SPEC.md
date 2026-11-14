# Koi — Product Spec (1.0)

Koi turns the small things you do each day into one honest score, so you always
know how your day is going and what would help. Three pillars, one number.

---

## 1. Core concepts

### Pillars
- **Habits**: recurring things you do (make bed, read 10 minutes).
- **Nutrition**: calories and nutrients against goals.
- **Exercise**: daily steps plus training across the week.

### Balance score (0–100%)
`balance = habits·wH + nutrition·wN + exercise·wE`, clamped 0…1, each pillar
already capped at 1.

**Focus presets** set the weights (chosen in onboarding, changeable in Profile):

| Focus | Habits | Nutrition | Exercise | Line |
|---|---|---|---|---|
| The All-Rounder (default) | ⅓ | ⅓ | ⅓ | For a bit of everything, equally. |
| The Ritualist | ½ | ¼ | ¼ | For building routines. Habits are half. |
| The Nourisher | ¼ | ½ | ¼ | For eating well. Nutrition is half. |
| The Mover | ¼ | ¼ | ½ | For training. Exercise is half. |

Every pillar always counts. No pillar can be switched off.

### Habits pillar
- `completed ÷ scheduled` for the day, 0 when nothing is scheduled.
- **Two-minute minimum**: each habit may have a minimum version
  ("read 1 page"). Doing only the minimum earns half credit for that habit.
- **Never miss twice**: the first missed scheduled day counts half and does not
  break the habit's own streak; a second miss in a row counts zero and breaks it.
- **Graduated** habits (see Habit coach) still show in Today, labeled
  "Part of you", and no longer count toward the score.

### Nutrition pillar
Average of each scored nutrient's contribution, plus calories if scored.
Each nutrient has a goal type:

| Goal type | Contribution |
|---|---|
| Reach (at or above) | `min(value / goal, 1)` |
| Limit (at or below) | `1` if `value ≤ goal`, else `goal / value` |
| Around | `1 − min(|value − goal| / goal, 1)` |
| Just track | not scored |

- Nothing logged today → nutrition is 0 (an untouched day earns nothing).
- A Limit that is still under goal earns credit in step with the day's eating:
  multiply by `min(caloriesEaten / calorieGoal, 1)`. One shake must not score
  sugar and sodium in full.

Default nutrients (user can add/remove/re-type):

| Key | Name | Unit | Goal | Step | Type |
|---|---|---|---|---|---|
| calories | Calories | kcal | 2,200 | 50 | Around |
| protein | Protein | g | 140 | 5 | Reach |
| fiber | Fiber | g | 30 | 1 | Reach |
| water | Water | oz | 100 | 8 | Reach |

Available to add: Added sugar (g, 36, Limit), Carbs (g, 250, Limit),
Fat (g, 70, Track), Sodium (mg, 2,300, Limit), and custom nutrients.

### Exercise pillar
`(steps + training) / 2`
- Steps: `min(steps / stepGoal, 1)` (default goal 8,000). Counts every day.
- Training, over a rolling 7 days (no Sunday reset): a day you train scores 1;
  a rest day scores `min(workoutsInLast7Days / weeklyTarget, 1)` (default 4).

### Streak
- A day counts when Balance ≥ **70%** (fixed for everyone).
- **Freezes**: one earned every 7 counting days in a row, at most 2 banked.
  A missed day spends a freeze automatically so the streak lives.
- Today never breaks the streak until the day is over.
- Show current and best.

---

## 2. Screens

Tab bar: **Hub · To-Do · Movement · Intake**. Swipe sideways anywhere to change
tab (horizontal scroll rows never change tab). Profile and Progress open in
place inside the Hub.

### Hub
- Header: wordmark, date, greeting with name ("Good evening, Sam."), person icon.
- **The dial** (hero): Balance as a half-arc bleeding off the left edge with
  ticks and a glass bead; three inner bars (Habits, Nutrition, Exercise) sized
  by weight. Big percentage top-right with "BALANCE".
- Hold and slide the dial to scrub back through the last 7 days.
- Tap a pillar label: a calm line opens under the dial (score, what's behind it,
  one action: Log food / Start workout; and Open tab). Tap again → its tab.
- Trend chip under the score: "↗ 6 vs last week", or "See progress" before a
  week of history. Tapping it, or the big number, opens Progress.
- Streak with flame, "best N".
- **Today**: habits and to-dos due today, open first then done. Shows 2 with
  "+N more" that expands in place. Tap the ring to complete (or swipe right);
  tap the words to open details in place (schedule, time, streak or quadrant,
  date, notes, Edit).
- Morning check-in card (first open of the day): yesterday's score and one
  suggestion; readiness when Health data exists.

### To-Do
- Habits (with today's check state) and to-dos.
- Views: List and Eisenhower matrix (Do now · Plan it / Quick one · Someday;
  urgent left column, important top row). Drag to-dos between quadrants.
- Tap a to-do: opens in place (date, notes, quadrant chips, Edit).
- Swipe right complete, swipe left delete.
- **Auto-urgent**: a dated to-do due today or tomorrow counts as urgent unless
  the user undoes it ("Due soon · marked urgent  Undo").
- Stale someday to-dos untouched 7 days ask "Keep / Let go".
- Archive (header icon): finished to-dos (moved a day after ticking) and paused
  habits, restorable.

**New to-do** (an event, not a form):
- Big title field, cursor ready, rotating prompt (What needs doing? / On your
  mind? / One thing… / What's next?).
- Dates in the words are parsed live (today, tomorrow, Friday, at 3pm) into a
  chip; tap the chip to ignore.
- A quadrant guess chip ("Sounds like Plan it").
- Required: pick one of four quadrant tiles (each shows dots for what's already
  there; picking ripples).
- When: Pick a day (inline calendar + optional time and duration) · Find a time
  (next free calendar slot) · No date.
- Notes behind a "+ Note" chip.
- One big button that names the result: "Add to Plan it · Fri".

**New habit**: same style. Title, note chip, How often (Daily, Weekly, Some days
with weekday circles, Monthly), When (Any time, Morning 8, Midday 12, Evening 7,
or exact time → reminder 10 min before unless done), optional two-minute
minimum, optional "after I…" stacking cue and identity ("who you're becoming").
Button: "Start · every day · 8:00 AM".

### Intake
- Dial: calories as the arc, every tracked nutrient as an inner bar.
- Food ring (LOG / "3 logged"): tap → food log.
- **Food log**: photo (camera or library), description, or both → AI estimate
  (calories, protein, carbs, fat, fiber, added sugar, sodium) → review and add.
  Meals list; tap a meal to edit numbers or re-estimate with more detail.
  Deleting a meal subtracts its numbers.
- Nutrient rows are quiet lines (name ⌄, number / goal unit, bar). Tap the name
  to open: goal line ("Reach 140 g or more · 64% scored"), quick-add chips
  (water: Glass +8, Mug +12, Bottle +16; protein: Snack +10, Meal +30; fiber:
  Fruit +4, Meal +8; calories: Snack +200, Meal +600), − / +. One open at a
  time. Drag the bar to set. Tap the number for a big counter sheet.
- Sliders icon: edit mode (remove nutrients, change goal type, add nutrient).
- Supplements as chips: tap to mark taken.

### Movement
- Dial: steps as the arc; inner bars = this week's workouts vs target.
- LOG ring: mark today trained.
- Steps quiet row (Walk +1000, Run +4000, − / +). From Apple Health when
  connected ("Steps · Health").
- Stats: Workouts (7 days), Avg steps, Best day.
- Dumbbell icon → **Workout journal**.

### Workout journal
Tabs: **Strength · Cardio**.

**Strength**
- **Today card**: Koi's pick, with Start / Go again. Pick logic: every lift has
  a group (push, pull, legs, core; guessed from the name, changeable); suggest
  the group rested longest, with your routine or last day for it and next-step
  weights. Understands upper/lower and full-body splits (Upper A/B alternate;
  after full body suggest a day off). After 3 training days in a row suggest
  rest or light. A routine planned for today wins.
- "Already did it": log the suggestion as last time's sets in one tap.
- Three tiles: **Just go** (empty workout, add as you go), **Build** (now or for
  later), **Koi presets** (Push day, Pull day, Leg day).
- Your routines (chips; hold to edit/delete). Planned (routines with a date).
- This week: workouts, sets, lb moved vs last week. Trends: sets per muscle
  group per week (8 weeks, 10–20 sets note); each lift's 12-week estimated max
  sparkline with a verdict (up 6% over 8 weeks / holding steady / stalled 3
  sessions / down).
- Your lifts: quiet rows (best, last session, trend arrow); tap for trend line
  and last 3 sessions; Full history sheet (best, est. 1RM chart, sessions).
- Past workouts (last 5 days) with Repeat.
- Import a plan from a screenshot, photo or pasted text into routines.

**Routine builder**: name (guessed from lifts: Push, Pull, Legs, Upper, Full
body), lifts (autocomplete, reorder, remove), sets × target reps, When (Any
time, Today, Tomorrow, pick a day). Start now / Save for later.

**Workout mode** (the doing screen)
- Header: wordmark and the workout clock.
- Lift chips (done = check, dimmed); + Add (inline field with suggestions);
  "Up next" chips suggest the lift you'd add next (learned from what usually
  follows; on-device model may reorder and explain).
- The set in hand: lift name, set dots (● ● ○), weight × reps huge (80pt).
  Tap a number to type it; drag up/down to step (5 lb / 1 rep); − / +.
- Plates per side under barbell lifts (drawn to scale; bar per lift, trap bar
  60 for deadlifts; "+5 each side" from last set; "use 180" when it can't load
  exactly). Long-press plates to set your gym's bar and plates.
- Context line: "Last 185 × 8, 8, 7 · [Try 190 × 8]" (tap to fill).
- Today's sets as pills (tap to edit, mark warm-up, delete).
- **Log set** button becomes the rest countdown (glass drains; tap to skip;
  hold for +15s and rest length). Rest remembered per lift.
- New best: numbers glow, "New best" pill, haptic.
- Supersets: hold a lift to pair with the next; alternate, rest after the pair.
- End workout → summary card (minutes, sets, lb moved, new bests, per-lift
  summary, share image) with Save as routine / Update routine.
- Bodyweight lifts show BW and track best reps.
- **Live Activity** (lock screen + Dynamic Island): workout clock, current lift,
  rest countdown, and the set in hand with a ✓ that logs it and starts rest
  without unlocking (queued if the app was closed).
- Progression: double progression. Every set at the top weight held its reps →
  add 5 lb (2.5 under 50); otherwise same weight, aim to hold the reps.
  Bodyweight: add a rep.
- Readiness "take it easy" → pick says go light and weights hold.

**Cardio**
- Outdoor run hero: GPS route, live pace, mile splits, Start run.
- Tiles: Treadmill (distance & time, live pace), Class (Pilates, Yoga, Spin,
  HIIT, Barre, Boxing, Dance, Stretch; minutes only), Other (swim, hike, bike).
- Usual activities to log again; This week (sessions, minutes, miles);
  Miles · 8 weeks bars; Bests (longest, fastest pace, best 5K); Your activities;
  Recent (tap a GPS run for its card).
- A session with no distance is a class: minutes, no pace.

### Progress (opens in Hub)
- Month · Week chips.
- Pillar summary for the scope (this month / this week / a tapped day) vs the
  previous one: Habits ("of what was scheduled, done"), Movement ("2 of 4
  workouts"), Intake ("average day against your goals"), with Balance.
- Month grid of daily Balance with each week's average; tap a day to focus the
  summary on it, tap again to return.

### Profile (opens in Hub)
Avatar (photo), name, "Since Nov 4", **Replay the tour**. Then quiet fold rows,
one open at a time, each with a summary: Body weight (log today with a ruler,
trend, direction, history), Your focus, Nutrition goals, Exercise goals (steps,
workouts a week), Notifications (Smart / Once a day / None + time),
Apple Health, Apple Calendar (sync timed to-dos), Smart notes (also send to
Apple Notes), iCloud backup, Tips & gestures.

### Smart note
A handle above the tab bar; swipe up to write freely. Koi offers one-tap logs
for what it finds: food (estimate), water, habits done, to-dos (on the day
named), workouts ("bench 185x5x3" logs sets; naming lifts plans today).
Uses on-device Apple Intelligence when available.

### Onboarding (7 steps)
Welcome → Name (+ optional beta email) → Your focus → Habits (pick at least 3)
→ About you (optional height/weight/age/sex → suggested targets) and targets →
Connect (Health, Calendar, notifications) → Ready (optional "tell me when Koi
officially drops" email). Back button on every step; progress bar; skip to
defaults. Then the tour.

### Tour
Dims the screen (deep blue) and points at real UI, ~12 steps: dial, pillars,
Progress chip, Profile, tabs, To-Do, Archive, Movement log, journal, intake bar,
edit nutrients, smart note (hands-on: swipe it up to finish). Skip in the corner.

### Notifications
- Modes: Smart (default), Once a day, None.
- Smart: nudges for habit times, nutrition gaps, movement, streak protection
  (including when a freeze is banked); each cancels itself once its goal is met.
- Daily check-in at the chosen time.
- Sunday recap with one habit coach suggestion: ease off (kept under half or
  mostly minimum), step up (90% for 4 weeks; old amount becomes the minimum),
  graduate (90% over 66 days), or stack a new one after your strongest.
  "Not now" waits two weeks.

### Widgets and controls
- Home: Balance (small/medium), Quick log, Habits / Habit rings (small, medium,
  large; tap a ring to log the habit).
- Lock screen: Balance, Balance + pillars, Next best action, Rest timer,
  Log a meal.
- Control Center / Action button: Log a meal (opens the camera).

---

## 3. Integrations

- **Apple Health**: steps, workouts (count as trained), body weight,
  sleep, HRV, resting heart rate. One preferred source per day for HRV/RHR/sleep
  (auto prefers wearables). Readiness: last night's sleep, HRV and RHR vs a
  30-day normal → Ready / Steady / Take it easy, with reasons.
- **Apple Calendar**: timed to-dos create events and stay in sync on edit,
  complete and delete; Find a time reads free slots.
- **iCloud backup**: automatic private backup; restore offered on a new phone.
- **Apple Notes** (optional): smart notes also saved there via a Shortcut.

## 4. Backend

Base URL `https://www.balancewithkoi.app`. Headers on every request:
`x-koi-app-token: <KOI_APP_TOKEN>`, `x-koi-device: <identifierForVendor>`.
Caps per device per day; 429 means "you've hit today's limit".

**POST /api/estimate** → food estimate
Request: `{ "text"?: string ≤500, "image"?: base64 JPEG, "mediaType"?: "image/jpeg" }`
Response:
```json
{ "calories": 540, "protein_g": 32, "carbs_g": 61, "fat_g": 18,
  "fiber_g": 7, "added_sugar_g": 6, "sodium_mg": 890,
  "confidence": 0.8, "description": "Chicken burrito bowl" }
```
Named brands and restaurant items use their published values.

**POST /api/workout-import** → routines from a photo or text
Request: same shape, text ≤8000. Response:
`{ "routines": [ { "name": "Upper A", "exercises": [ { "name": "Bench press", "sets": 3, "reps": 8 } ] } ] }`

Errors: 401 bad token, 413 too large, 429 limit, 5xx try again. Show calm,
specific messages ("Couldn't reach Koi's estimator. Check your connection.").

## 5. Analytics (local event hooks, anonymous)

Onboarding.step / completed, Screen.opened {screen}, Food.loggedWithAI,
Food.aiFailed, Task.completed, Task.placed {quadrant, dated}, Habit.completed,
Note.saved, Workout.started {kind}, Workout.setLogged, Workout.finished,
Workout.routineBuilt, Cardio.runStarted, Cardio.logged {kind},
Hub.pillarOpened {pillar}, Tour.ended {at}. Never names, meals or numbers.

## 6. Privacy

All data stays on device and in the user's private iCloud. Food photos and
descriptions go to the estimate endpoint only when the user logs food. No
accounts required.
