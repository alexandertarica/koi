const AI_PROXY_URL = "https://koi-demo-api.vercel.app/api/demo-ai";
const FEEDBACK_URL = "https://koi-demo-api.vercel.app/api/demo-feedback";
const EVENT_URL = "https://koi-demo-api.vercel.app/api/demo-event";
const respondentId = crypto.randomUUID();
let respondentStartedAt = "";
const respondent = { firstName: "", feedbackBusy: false, feedbackError: "", morningCoachRequested: false };
const root = document.querySelector("#app-root");
const header = document.querySelector("#app-header");
const view = document.querySelector("#app-view");
const tabBar = document.querySelector("#tab-bar-wrap");
const demoBar = document.querySelector(".demo-bar");
const demoFooter = document.querySelector(".demo-footer");
const photoInput = document.querySelector("#photo-input");

const initialState = () => ({
  stage: "app",
  guidedMode: false,
  guidedStep: "start",
  guidedStartBalance: 0,
  name: "",
  focus: "balanced",
  health: false,
  calendar: false,
  tab: "Hub",
  tourVisible: true,
  showAllToday: false,
  meals: [],
  proteinGoalToday: 140,
  balanceFloor: 0,
  goalDate: new Date().toLocaleDateString("en-CA"),
  tasks: [],
  habits: [],
  steps: 0,
  streak: 0,
  bestStreak: 0,
  didTrain: false,
  pondOpen: false,
  coachSuggestion: null,
  coachLoading: false,
  coachError: "",
  coachEvent: "morning",
  foodOpen: false,
  foodText: "",
  foodPhoto: null,
  foodPreview: "",
  foodResult: null,
  editingMealID: null,
  manualMode: false,
  error: "",
  estimating: false,
  smartNoteOpen: false,
  smartNoteText: "",
  smartNoteMessage: "",
  planText: "",
  planPhoto: null,
  planResult: null,
  importingPlan: false,
  planError: "",
});

try { localStorage.removeItem("koi.browser-demo-state"); } catch { /* The demo still works when storage is disabled. */ }
let state = initialState();
let demoDeviceID = "";
try {
  demoDeviceID = localStorage.getItem("koi.browser-demo-id") || "";
  if (!demoDeviceID) {
    demoDeviceID = crypto.randomUUID();
    localStorage.setItem("koi.browser-demo-id", demoDeviceID);
  }
} catch {
  demoDeviceID = crypto.randomUUID();
}

const icons = {
  day: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="4" width="17" height="16" rx="2.2"/><path d="M7.5 8h.1M12 8h.1M16.5 8h.1M7.5 12h.1M12 12h.1M16.5 12h.1M7.5 16h.1M12 16h.1" stroke-width="2.3"/></svg>',
  camera: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 7.5h4l1.7-2h6.6l1.7 2h4v11H3z"/><circle cx="12" cy="13" r="3.5"/></svg>',
  next: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9.5"/><path d="M7.5 12h9M12.5 8l4 4-4 4"/></svg>',
  hub: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.7 20 7.3v9.4l-8 4.6-8-4.6V7.3z"/><path d="m7.4 9.8 2.3-1.3 2.3 1.3v2.6l-2.3 1.3-2.3-1.3zm4.6 2.6 2.3-1.3 2.3 1.3V15l-2.3 1.3L12 15z"/></svg>',
  todo: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6h11M9 12h11M9 18h11"/><path d="m3.5 6 1 1 2-2m-3 7 1 1 2-2m-3 7 1 1 2-2"/></svg>',
  move: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="14" cy="4.5" r="1.6"/><path d="m11.5 8 3 1.2 2.4 3.1m-5.3-4.3-2.8 3.1-3.2.6m6-.2-1 4.1-3.2 4m4.2-4.1 3.6 2.1 2.5 3.2"/></svg>',
  intake: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M19.8 4.2C10 4 5 7.6 5 13.1c0 3.4 2.2 5.7 5.3 5.7 6 0 9.6-6 9.5-14.6Z"/><path d="M4 21c2.6-5 6.5-8.5 12-11"/></svg>',
  user: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="8" r="3.4"/><path d="M4.5 20c.7-4 3.2-6 7.5-6s6.8 2 7.5 6"/></svg>',
};

function safe(value = "") {
  return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}

function trackDemoEvent(event) {
  fetch(EVENT_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ respondentId, event, timestamp: new Date().toISOString() }),
    keepalive: true,
  }).catch(() => {});
}

function dateLabel() {
  return new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" }).format(new Date()).toUpperCase();
}

function localISODate(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${values.year}-${values.month}-${values.day}`;
}

function ordinal(value) {
  const mod100 = value % 100;
  if (mod100 >= 11 && mod100 <= 13) return `${value}th`;
  return `${value}${({ 1: "st", 2: "nd", 3: "rd" })[value % 10] || "th"}`;
}

function sampleEventDate() {
  const date = new Date();
  date.setDate(date.getDate() + 1);
  date.setHours(9, 0, 0, 0);
  return date;
}

function tomorrowAtSeven() {
  const date = new Date();
  date.setDate(date.getDate() + 1);
  date.setHours(7, 0, 0, 0);
  return date;
}

function coachRank() { return state.pondViewed || state.guidedMode ? "3rd of 5 in your pond" : null; }

function renderCoachCard() {
  if (!state.coachLoading && !state.coachSuggestion && !state.coachError) return "";
  const suggestion = state.coachSuggestion;
  return `<section class="coach-card" aria-live="polite"><p class="small-label">✦ KOI COACH</p>
    ${state.coachLoading ? '<p class="coach-message">Finding one small next step…</p>' : suggestion ? `<p class="coach-message">${safe(suggestion.message)}</p><div class="coach-actions"><button class="glass-chip" type="button" data-action="accept-coach">Accept</button><button class="quiet-link" type="button" data-action="dismiss-coach">Not now</button></div>` : `<p class="error-copy">${safe(state.coachError)}</p><button class="quiet-link" type="button" data-action="retry-coach">Try again</button>`}
  </section>`;
}

const guidedCaptions = {
  start: ["Start with a sample day", "Habits and food are already part of today. Log a workout and see how the pillars work together."],
  workout: ["Pillars talk to each other", "The workout changes the day. Koi checks your protein goal and offers one useful next step."],
  target: ["Your target adapts to training", "Accepting raises today's protein target only. It leaves Balance where it was until food closes the gap."],
  photo: ["AI estimates from a photo", "This unbranded sample bar photo goes through the live meal estimate service and becomes a real meal entry."],
  balance: ["One score, all three pillars", "The meal and workout now count in today's Balance. Next, see the clearly labeled sample Pond."],
  pond: ["Friends keep you consistent", "This sample Pond has five friends and an active sprint. Your sample standing is 3rd of 5."],
  coach: ["Koi plans around your schedule", "The sample schedule is Class at 9:00 AM. Koi suggests a 3-mile run before it and adds a dated to-do."],
  todo: ["Now try it yourself", "The run is in To-Do for tomorrow at 7:00 AM. Start fresh for an empty day, or leave the guide and explore."],
};

function renderCaptionPanel() {
  const panel = document.querySelector("#caption-panel");
  if (!panel) return;
  document.querySelector(".demo-presentation")?.classList.toggle("guided-active", state.guidedMode);
  panel.hidden = !state.guidedMode;
  if (!state.guidedMode) { panel.innerHTML = ""; return; }
  const [title, defaultDescription] = guidedCaptions[state.guidedStep] ?? guidedCaptions.start;
  const description = state.guidedStep === "start"
    ? `Your sample day begins at ${state.guidedStartBalance}% Balance. Habits and food are already part of today. Log a workout and see how the pillars work together.`
    : state.guidedStep === "balance"
      ? `Balance moved from ${state.guidedStartBalance}% to ${getBalance()}%. The meal and workout now count in today's score. Next, see the clearly labeled sample Pond.`
      : defaultDescription;
  panel.innerHTML = `<p class="caption-kicker">GUIDED DEMO · SAMPLE DAY</p><h2>${safe(title)}</h2><p>${safe(description)}</p>${state.guidedStep === "todo" ? '<p class="sample-note">Friends, starting data and the 9:00 AM class are samples.</p><button class="primary-button" type="button" data-action="show-feedback">Help shape Koi →</button><button class="quiet-link" type="button" data-action="start-fresh">Start fresh</button>' : ""}<button class="caption-exit" type="button" data-action="exit-guided">${state.guidedStep === "start" ? "Skip guided demo" : "Exit guided demo"}</button>`;
}

function renderPond() {
  const rows = [["Maya",84],["Jordan",78],["You",72],["Riley",68],["Sam",65]];
  const finish = new Date();
  finish.setDate(finish.getDate() + ((4 - finish.getDay() + 7) % 7 || 7));
  const finishText = new Intl.DateTimeFormat(undefined, { weekday: "short", month: "short", day: "numeric" }).format(finish);
  return `<div class="app-mode pond-screen"><p class="sample-badge">SAMPLE POND · FICTIONAL MEMBERS</p><p class="small-label">ACTIVE SPRINT</p><h1 class="view-heading">Highest Nutrition + Exercise by ${safe(finishText)}</h1><p class="view-note">Losers buy the winner a coffee</p><p class="pond-countdown">5 days left</p><p class="small-label">LEADERBOARD</p><div class="pond-leaderboard">${rows.map(([name, score], index) => `<div class="pond-row ${index === 2 ? "you" : ""}"><div class="pond-row-top"><span>${index === 0 ? "♛" : index + 1}　${name}</span><strong>${score}%</strong></div><div class="pond-track"><i style="width:${score}%"></i><b style="left:${score}%"></b></div></div>`).join("")}</div><p class="status-message">Sample standings for this demo. Friends and scores are fictional.</p><button class="primary-button" type="button" data-action="return-from-pond">Back to your day</button></div>`;
}

function getBalance() {
  const habit = state.habits.length ? state.habits.filter((item) => item.done).length / state.habits.length : 0;
  const nutrition = getNutritionScore();
  const movement = Math.min(state.steps / 8000, 1) * .6 + (state.didTrain ? .4 : 0);
  const weights = state.focus === "habits" ? [.5, .25, .25] : state.focus === "nutrition" ? [.25, .5, .25] : state.focus === "exercise" ? [.25, .25, .5] : [1 / 3, 1 / 3, 1 / 3];
  const current = Math.round((habit * weights[0] + nutrition * weights[1] + movement * weights[2]) * 100);
  return Math.max(current, state.balanceFloor || 0);
}

function getNutritionScore() {
  if (!state.meals.length) return 0;
  const totals = nutritionTotals();
  return [
    1 - Math.min(Math.abs(totals.calories - 2200) / 2200, 1),
    Math.min(totals.protein / state.proteinGoalToday, 1),
    Math.min(totals.fiber / 30, 1),
  ].reduce((sum, value) => sum + value, 0) / 3;
}

function renderDial({ value, kind = "balance", bars = [], labels = true, logged = 0 }) {
  const score = Math.max(0, Math.min(100, Number(value) || 0));
  const cx = 0, cy = 186, radius = 165;
  const point = (angle, r) => [cx + Math.cos(angle) * r, cy + Math.sin(angle) * r];
  const arcPath = `M 0 21 A ${radius} ${radius} 0 0 1 0 351`;
  const ticks = Array.from({ length: 72 }, (_, index) => {
    const angle = -Math.PI / 2 + (Math.PI * index) / 71;
    const major = index % 5 === 0;
    const valueTick = Math.abs(index / 71 * 100 - score) <= 100 / 71 / 2;
    const r1 = radius + 7, r2 = radius + (valueTick ? 22 : major ? 17 : 12);
    const [x1, y1] = point(angle, r1), [x2, y2] = point(angle, r2);
    const lit = index / 71 * 100 <= score;
    return `<line class="dial-tick ${lit ? "lit" : ""} ${major ? "major" : ""} ${valueTick ? "value-tick" : ""}" x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}"/>`;
  }).join("");
  const beadAngle = -Math.PI / 2 + Math.PI * score / 100;
  const [bx, by] = point(beadAngle, radius);
  const barsMarkup = bars.map((bar, index) => {
    const y = 149 + index * 25;
    const width = 104 * Math.max(.1, Math.min(1, bar.weight ?? 1));
    const fill = width * Math.max(0, Math.min(1, bar.value / 100));
    return `<g class="dial-bar"><text x="27" y="${y}" class="dial-bar-label">${safe(bar.name)}</text><line x1="27" y1="${y + 8}" x2="${(27 + width).toFixed(1)}" y2="${y + 8}" class="dial-bar-track"/><line x1="27" y1="${y + 8}" x2="${(27 + fill).toFixed(1)}" y2="${y + 8}" class="dial-bar-fill"/></g>`;
  }).join("");
  const labelPositions = kind === "balance" ? [
    ["habits", 126, 24, bars[0]?.value ?? 0], ["nutrition", 186, 46, bars[1]?.value ?? 0], ["exercise", 244, 69, bars[2]?.value ?? 0],
  ] : kind === "intake" ? [["protein", 132, 24, bars[0]?.value ?? 0], ["fiber", 235, 66, bars[1]?.value ?? 0]] : [["steps", 132, 24, bars[0]?.value ?? 0], ["workouts", 235, 66, bars[1]?.value ?? 0]];
  const labelsMarkup = labels ? labelPositions.map(([name, y, x, pct]) => `<g class="dial-label"><text x="${x}" y="${y}" class="dial-label-name">${name}</text><text x="${x}" y="${y + 15}" class="dial-label-value">${Math.round(pct)}%</text></g>`).join("") : "";
  return `<svg class="koi-dial ${kind}-dial" viewBox="0 0 300 372" preserveAspectRatio="none" aria-hidden="true">
    ${ticks}<path class="dial-arc-track" d="${arcPath}"/><path class="dial-arc-progress" d="${arcPath}" pathLength="100" style="--dial-value:${score};"/>
    ${barsMarkup}${labelsMarkup}<circle class="dial-bead-halo" cx="${bx.toFixed(1)}" cy="${by.toFixed(1)}" r="9"/><circle class="dial-bead" cx="${bx.toFixed(1)}" cy="${by.toFixed(1)}" r="4.3"/>
  </svg>`;
}

function renderHeader() {
  if (state.stage !== "app") {
    const title = ["respondent", "feedback"].includes(state.stage) ? "YOUR THOUGHTS" : state.stage === "thanks" ? "THANK YOU" : state.stage === "connect" ? "CONNECT" : "FOCUS";
    header.innerHTML = `<div class="header-row"><img class="wordmark" src="assets/wordmark.png" alt="Koi"><span class="header-section">${title}</span></div>`;
    return;
  }

  const section = state.foodOpen ? "Log food" : state.pondOpen ? "Your Koi Pond" : "";
  const right = state.foodOpen || state.pondOpen
    ? `<button class="close-screen" type="button" data-action="${state.pondOpen ? "close-pond" : "close-food"}" aria-label="Close ${state.pondOpen ? "pond" : "meal composer"}">×</button>`
    : `<button class="header-icon" type="button" data-action="profile" aria-label="Open profile">${icons.user}</button>`;
  header.innerHTML = `<div class="header-row"><img class="wordmark" src="assets/wordmark.png" alt="Koi">${right}</div>
    <div class="date-label">${dateLabel()}</div>${section ? `<h1 class="screen-title">${section}</h1>` : ""}`;
}

const privacyNote = "Student project built at the Cal Poly hackathon. We only keep your first name and answers (plus email if you add it).";

function renderRespondentStart() {
  return `<section class="onboarding-view respondent-view"><p class="step-label">YOUR THOUGHTS</p><h1 class="welcome-title">Your first name</h1><p class="view-note">Your answers help us make Koi better.</p><form id="respondent-name-form"><label class="respondent-name-label" for="respondent-first-name">FIRST NAME</label><input class="name-field" id="respondent-first-name" name="firstName" maxlength="40" autocomplete="given-name" required placeholder="First name"><button class="primary-button" type="submit">Continue</button></form><button class="quiet-link skip-questions-link" type="button" data-action="back-to-koi">Back to Koi</button><p class="privacy-note">${privacyNote}</p></section>`;
}

function renderFeedbackForm() {
  const question = (key, title) => `<fieldset class="feedback-question"><legend>${title}</legend><div class="feedback-choices">${["Yes", "Maybe", "No"].map((choice) => `<label><input type="radio" name="${key}" value="${choice}" required><span>${choice}</span></label>`).join("")}</div></fieldset>`;
  return `<section class="onboarding-view feedback-view"><p class="step-label">YOUR FEEDBACK</p><h1 class="step-heading">A few quick questions.</h1><form id="feedback-form" class="feedback-form">${question("wouldUse", "Would you use Koi?")}${question("wouldPay", "Would you pay $2.99/month for the AI coach?")}<label class="feedback-field"><span>What would make you use it every day?</span><input name="dailyUse" maxlength="240" placeholder="One line, optional"></label><label class="feedback-field"><span>Email, if you want Koi when it launches</span><input name="email" type="email" maxlength="254" autocomplete="email" placeholder="Optional"></label><p class="privacy-note">${privacyNote}</p>${respondent.feedbackError ? `<p class="feedback-error" role="alert">${safe(respondent.feedbackError)}</p>` : ""}<button class="primary-button" type="submit" ${respondent.feedbackBusy ? "disabled" : ""}>${respondent.feedbackBusy ? "Sending…" : "Send answers"}</button></form><button class="quiet-link" type="button" data-action="back-to-koi">Back to Koi</button></section>`;
}

function renderThanks() {
  return `<section class="onboarding-view respondent-view thanks-view"><div><p class="step-label">RECEIVED</p><h1 class="step-heading">Thanks, ${safe(respondent.firstName)}!</h1><p class="view-note">Your note helps shape what Koi becomes.</p></div><div class="onboarding-spacer"></div><button class="primary-button" type="button" data-action="next-person">Next person</button></section>`;
}

function renderWelcome() {
  return `<section class="onboarding-view">
    <p class="step-label">1 of 3</p>
    <h1 class="welcome-title">One score for your habits, food and movement.</h1>
    <ul class="feature-list">
      <li class="feature-row"><span class="feature-icon">${icons.day}</span><span>See your day at a glance</span></li>
      <li class="feature-row"><span class="feature-icon">${icons.camera}</span><span>Log food with a photo or a sentence</span></li>
      <li class="feature-row"><span class="feature-icon">${icons.next}</span><span>Know what to do next</span></li>
    </ul>
    <input class="name-field" id="first-name" maxlength="28" autocomplete="given-name" placeholder="First name (optional)" aria-label="First name (optional)" value="${safe(state.name)}">
    <button class="quiet-link" type="button" data-action="skip-setup">Skip setup, use the defaults</button>
    <button class="quiet-link guided-entry" type="button" data-action="start-guided">Try the guided demo</button>
    <div class="onboarding-spacer"></div>
    <button class="primary-button" type="button" data-action="next-connect">Next</button>
  </section>`;
}

function renderConnect() {
  const row = (key, symbol, title, detail, checked) => `<div class="connect-row">
    <span class="connect-icon" aria-hidden="true">${symbol}</span>
    <span class="connect-copy"><strong>${title}</strong><small>${detail}</small></span>
    <button class="switch" type="button" role="switch" aria-checked="${checked}" aria-label="${title}" data-action="toggle-${key}"></button>
  </div>`;
  return `<section class="onboarding-view">
    <p class="step-label">2 of 3</p>
    <h1 class="step-heading">Bring the useful parts of your day together.</h1>
    <div class="connect-list">
      ${row("health", "♡", "Apple Health", "Steps, workouts and sleep", state.health)}
      ${row("calendar", "▦", "Calendar", "To-dos and plans", state.calendar)}
    </div>
    <p class="optional-note">Both are optional. You can connect them later in Profile.</p>
    <p class="demo-permissions-note">This browser preview does not request Health or Calendar access.</p>
    <div class="onboarding-spacer"></div>
    <button class="primary-button" type="button" data-action="next-focus">Next</button>
  </section>`;
}

const focusOptions = [
  ["balanced", "Balanced", "All three count equally"],
  ["habits", "Habits", "Give habits a little more weight"],
  ["nutrition", "Nutrition", "Give nutrition a little more weight"],
  ["exercise", "Exercise", "Give movement a little more weight"],
];

function renderFocus() {
  return `<section class="onboarding-view">
    <p class="step-label">3 of 3</p>
    <h1 class="step-heading">Choose what matters most.</h1>
    <p class="view-note">You can change this in Profile.</p>
    <div class="focus-list">${focusOptions.map(([value, title, detail]) => `<button type="button" class="focus-choice" aria-pressed="${state.focus === value}" data-action="select-focus" data-value="${value}"><span><strong>${title}</strong><small>${detail}</small></span><i class="focus-dot"></i></button>`).join("")}</div>
    <div class="onboarding-spacer"></div>
    <button class="primary-button" type="button" data-action="start-demo">Start</button>
  </section>`;
}

function renderHub() {
  const score = getBalance();
  const habitPct = state.habits.length ? Math.round(state.habits.filter((item) => item.done).length / state.habits.length * 100) : 0;
  const nutritionPct = Math.round(getNutritionScore() * 100);
  const exercisePct = Math.min(Math.round(state.steps / 8000 * 100 + (state.didTrain ? 30 : 0)), 100);
  const greeting = new Date().getHours() >= 22 || new Date().getHours() < 5 ? "Still water" : new Date().getHours() < 12 ? "Good morning" : new Date().getHours() < 18 ? "Good afternoon" : "Good evening";
  const name = state.name ? `, ${safe(state.name)}` : "";
  const allItems = [
    ...state.habits.map((item) => `<div class="demo-habit"><button class="habit-ring ${item.done ? "checked" : ""}" type="button" data-action="toggle-habit" data-id="${item.id}" aria-label="${item.done ? "Uncheck" : "Check"} ${safe(item.title)}">${item.done ? "✓" : safe(item.title.slice(0, 1).toUpperCase())}</button><span>${safe(item.title)}</span></div>`),
    ...state.tasks.map((item) => `<div class="demo-task"><button class="task-check ${item.done ? "checked" : ""}" type="button" data-action="toggle-task" data-id="${item.id}" aria-label="${item.done ? "Uncheck" : "Check"} ${safe(item.title)}">${item.done ? "✓" : ""}</button><span>${safe(item.title)}</span></div>`),
  ];
  const items = (state.showAllToday ? allItems : allItems.slice(0, 2)).join("");
  const weights = state.focus === "habits" ? [.5, .25, .25] : state.focus === "nutrition" ? [.25, .5, .25] : state.focus === "exercise" ? [.25, .25, .5] : [1/3, 1/3, 1/3];
  return `<div class="app-mode">
    ${state.guidedMode ? '<p class="sample-day-label">SAMPLE SCHEDULE · CLASS 9:00 AM</p>' : ""}
    <h1 class="hub-greeting">${greeting}${name}.</h1>
    ${state.guidedMode ? "" : '<p class="sample-schedule-line">Sample schedule: Class 9:00 AM</p>'}
    <div class="hub-layout">
      ${renderDial({ value: score, bars: [{name:"HABITS",value:habitPct,weight:weights[0]},{name:"NUTRITION",value:nutritionPct,weight:weights[1]},{name:"EXERCISE",value:exercisePct,weight:weights[2]}] })}
      <button class="pond-chip" type="button" data-action="open-pond">♧ Go to pond</button>
      <button class="progress-chip" type="button" data-action="show-progress">See progress</button>
      <div class="score-block"><div class="score-value">${score}<span>%</span></div><div class="score-label">BALANCE</div></div>
      <div class="streak-block"><img class="streak-flame" src="assets/flame.svg" alt=""><span class="streak-count">${state.streak}</span><span class="streak-label">DAY STREAK</span><span class="streak-best">best ${state.bestStreak}</span></div>
    </div>
    <div class="today-block">
      <div class="section-row"><span>TODAY</span>${state.habits.length + state.tasks.length > 2 ? `<button type="button" class="more" data-action="show-all">${state.showAllToday ? "Show fewer" : `+${state.habits.length + state.tasks.length - 2} more`}</button>` : ""}</div>
      ${items || '<p class="empty-copy">Your day is open. Choose one small thing to begin.</p>'}
      <button class="tour-chip" type="button" data-action="tour" ${state.tourVisible ? "" : "hidden"}>◎ Show me around <span aria-hidden="true">×</span></button>
    </div>
    <div class="quick-add-row"><button class="glass-chip" type="button" data-action="tab" data-tab="To-Do">+ Habit</button><button class="glass-chip" type="button" data-action="tab" data-tab="To-Do">+ To-do</button><button class="glass-chip" type="button" data-action="tab" data-tab="Intake">Log food</button></div>
  </div>`;
}

function renderTodo() {
  const habits = state.habits.map((item) => `<div class="demo-habit"><button class="habit-ring ${item.done ? "checked" : ""}" type="button" data-action="toggle-habit" data-id="${item.id}" aria-label="${item.done ? "Uncheck" : "Check"} ${safe(item.title)}">${item.done ? "✓" : safe(item.title.slice(0,1).toUpperCase())}</button><span>${safe(item.title)}</span></div>`).join("");
  const tasks = state.tasks.map((item) => `<div class="demo-task"><button class="task-check ${item.done ? "checked" : ""}" type="button" data-action="toggle-task" data-id="${item.id}" aria-label="${item.done ? "Uncheck" : "Check"} ${safe(item.title)}">${item.done ? "✓" : ""}</button><span>${safe(item.title)}${item.dueAt ? `<small class="task-due">${safe(new Intl.DateTimeFormat(undefined,{weekday:"short",hour:"numeric",minute:"2-digit"}).format(new Date(item.dueAt)))}</small>` : ""}</span></div>`).join("");
  return `<div class="app-mode">${state.guidedMode ? '<p class="sample-day-label">SAMPLE SCHEDULE · CLASS 9:00 AM</p>' : ""}<h1 class="view-heading">Practice.</h1><p class="view-note">A little room for what matters.</p>
    <p class="small-label">HABITS</p>${habits || '<p class="empty-copy">Your habits will settle here.</p>'}
    <form class="task-form" data-form="habit"><input name="title" maxlength="80" placeholder="A habit to begin" aria-label="A habit to begin"><button type="submit">Add</button></form>
    <p class="small-label">TO-DOS</p>${tasks || '<p class="empty-copy">Your list is clear.</p>'}
    <form class="task-form" data-form="task"><input name="title" maxlength="100" placeholder="What is next?" aria-label="What is next?"><button type="submit">Add</button></form>
  </div>`;
}

function renderMovement() {
  const routine = state.planResult ? `<div class="result-card"><p class="small-label">PLAN READY</p><h2 class="view-heading">${safe(state.planResult.name)}</h2>${state.planResult.exercises.map((item) => `<div class="nutrient-line"><span>${safe(item.name)}</span><span>${item.sets} × ${item.reps}</span></div>`).join("")}</div>` : "";
  const workoutCount = state.didTrain ? 1 : 0;
  const stepPercent = Math.min(state.steps / 8000 * 100, 100);
  return `<div class="app-mode"><div class="tab-title-row"><div><h1 class="view-heading">Movement.</h1><p class="view-note">Small steps count.</p></div><button class="header-icon" type="button" data-action="profile" aria-label="Open profile">${icons.user}</button></div>
    <div class="movement-layout">${renderDial({value:stepPercent,kind:"movement",bars:[{name:"STEPS",value:stepPercent,weight:.72},{name:"WORKOUTS",value:workoutCount?100:0,weight:.54}],labels:true,logged:workoutCount})}<div class="movement-score"><strong>${state.steps.toLocaleString()}</strong><span>STEPS</span><small>of 8,000</small></div><button class="movement-log" type="button" data-action="toggle-workout"><span class="log-circle">${workoutCount ? "✓" : "LOG"}</span><span>${workoutCount ? "1 logged" : "Log workout"}</span></button></div>
    <div class="movement-stats"><div><strong>${workoutCount}</strong><span>WORKOUTS · 7 DAYS</span></div><div><strong>${Math.round(state.steps / 1000 * 10) / 10}k</strong><span>AVG STEPS</span></div><div><strong>${state.steps ? state.steps.toLocaleString() : "—"}</strong><span>BEST DAY</span></div></div>
    <div class="quick-add-row"><button class="glass-chip" type="button" data-action="steps" data-delta="-500">− 500</button><button class="glass-chip" type="button" data-action="steps" data-delta="500">+ 500 steps</button></div>
    <div class="nutrient-list"><p class="small-label">WORKOUT PLAN</p><p class="view-note">Read text or a photo into a simple routine.</p>
      <textarea class="food-field" id="plan-text" rows="3" maxlength="8000" placeholder="Bench press 3×8, row 3×10">${safe(state.planText)}</textarea>
      <div class="quick-add-row"><button class="glass-chip" type="button" data-action="import-plan">${state.importingPlan ? "Reading…" : "Read plan"}</button><button class="glass-chip" type="button" data-action="pick-plan-photo">Upload a photo</button></div>
      ${state.planError ? `<p class="error-copy">${safe(state.planError)}</p>` : ""}${routine}
    </div>
  </div>`;
}

function renderIntake() {
  const totals = state.meals.reduce((all, meal) => ({
    calories: all.calories + meal.calories,
    protein: all.protein + meal.protein,
    carbs: all.carbs + meal.carbs,
    fat: all.fat + meal.fat,
    fiber: all.fiber + meal.fiber,
    sugar: all.sugar + meal.sugar,
    sodium: all.sodium + meal.sodium,
  }), { calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, sugar: 0, sodium: 0 });
  if (state.foodOpen) return renderFoodComposer(totals);
  const mealRows = state.meals.map((meal) => `<div class="nutrient-line"><span>${safe(meal.description)}</span><span>${Math.round(meal.calories)} kcal</span></div>`).join("");
  const kcalPct = Math.min(totals.calories / 2200 * 100, 100);
  const nutrients = [["Protein",totals.protein,state.proteinGoalToday,"g"],["Carbs",totals.carbs,250,"g"],["Fat",totals.fat,70,"g"],["Fiber",totals.fiber,30,"g"],["Added sugar",totals.sugar,36,"g"],["Sodium",totals.sodium,2300,"mg"]];
  return `<div class="app-mode"><div class="tab-title-row"><div><h1 class="view-heading">Intake.</h1><p class="view-note">A steady picture of the day.</p></div><button class="header-icon" type="button" data-action="profile" aria-label="Open profile">${icons.user}</button></div>
    <div class="intake-layout">${renderDial({value:kcalPct,kind:"intake",bars:[{name:"PROTEIN",value:Math.min(totals.protein/state.proteinGoalToday*100,100),weight:.62},{name:"FIBER",value:Math.min(totals.fiber/30*100,100),weight:.46}],labels:true,logged:state.meals.length})}<div class="intake-score"><strong>${Math.round(totals.calories).toLocaleString()}</strong><span>CALORIES</span><small>of 2,200</small></div><button class="intake-log" type="button" data-action="open-food"><span class="log-circle">${state.meals.length ? state.meals.length : "LOG"}</span><span>${state.meals.length ? `${state.meals.length} logged` : "Add a meal"}</span></button></div>
    ${state.proteinGoalToday !== 140 ? '<p class="goal-adjustment-note">Adjusted for today\'s workout</p>' : ""}
    <div class="nutrient-list quiet-nutrients">${nutrients.map(([label,value,goal,unit]) => `<div class="nutrient-progress"><div class="nutrient-line"><span>${label}</span><span>${Math.round(value)} / ${goal} ${unit}</span></div><div class="nutrient-track"><i style="width:${Math.min(value/goal*100,100)}%"></i></div></div>`).join("")}</div>
    ${state.guidedMode && ["target", "photo"].includes(state.guidedStep) ? '<button class="primary-button sample-photo-button" type="button" data-action="use-sample-photo">Use sample photo</button>' : ""}
    <p class="small-label">TODAY</p>${mealRows || '<p class="empty-copy">Your meals will settle here.</p>'}<button class="primary-button" type="button" data-action="open-food">Log food</button>
  </div>`;
}

function renderFoodComposer(totals = null) {
  if (!totals) totals = state.meals.reduce((all, meal) => ({ calories: all.calories + meal.calories }), { calories: 0 });
  if (state.foodResult && !state.manualMode && state.editingMealID === null) {
    const result = state.foodResult;
    return `<div class="app-mode">
      <div class="result-top"><span class="result-kcal">~${Math.round(result.calories)} kcal</span>${result.source === "manual" ? "" : `<span class="result-sure">${Math.round(result.confidence * 100)}% sure</span>`}</div>
      <p class="result-description">${safe(result.description)}</p>
      <p class="result-macros">P ${Math.round(result.protein)}g · C ${Math.round(result.carbs)}g · F ${Math.round(result.fat)}g</p>
      <p class="result-added">Added to today's totals.</p>
      <div class="quick-add-row"><button class="glass-chip" type="button" data-action="edit-food">Fix numbers</button><button class="glass-chip" type="button" data-action="log-another">Log another</button></div>
      ${result.imageURL ? `<img class="meal-preview" src="${result.imageURL}" alt="Meal photo">` : ""}
      <div class="nutrient-list"><p class="small-label">TODAY · ${Math.round(totals.calories).toLocaleString()} KCAL</p>${state.meals.map((meal) => `<div class="nutrient-line"><span>${safe(meal.description)}</span><span>${Math.round(meal.calories)} kcal</span></div>`).join("")}</div>
    </div>`;
  }

  if (state.editingMealID !== null) {
    const result = state.foodResult;
    return `<div class="app-mode"><h2 class="view-heading">Fix numbers</h2><label class="small-label" for="edit-meal-name">MEAL</label><input id="edit-meal-name" class="food-field" value="${safe(result.description)}">
      <div class="nutrient-fields">${nutrientInput("Calories", "calories", result.calories, "kcal")}${nutrientInput("Protein", "protein", result.protein, "g")}${nutrientInput("Carbs", "carbs", result.carbs, "g")}${nutrientInput("Fat", "fat", result.fat, "g")}${nutrientInput("Fiber", "fiber", result.fiber, "g")}${nutrientInput("Added sugar", "sugar", result.sugar, "g")}${nutrientInput("Sodium", "sodium", result.sodium, "mg")}</div>
      <button class="primary-button" type="button" data-action="save-edit">Save</button><button class="quiet-link" type="button" data-action="delete-meal">Delete meal</button><button class="quiet-link" type="button" data-action="cancel-edit">Cancel</button>
    </div>`;
  }

  const text = state.foodText;
  const retry = state.error && (text.trim() || state.foodPhoto) ? '<button class="quiet-link" type="button" data-action="retry-food">Try again</button>' : "";
  return `<div class="app-mode">
    <textarea class="food-field" id="food-description" rows="2" maxlength="500" placeholder="Describe your meal (optional)">${safe(text)}</textarea>
    ${state.foodPhoto ? `<p class="status-message">Photo ready${state.foodPhoto.name ? ` · ${safe(state.foodPhoto.name)}` : ""}</p>` : ""}
    ${state.foodPreview ? `<img class="meal-preview" src="${state.foodPreview}" alt="Selected meal photo">` : ""}
    <button class="photo-row" type="button" data-action="take-photo"><span>◎</span><span>Take a photo</span><span class="photo-spark">✦</span></button>
    <button class="photo-row" type="button" data-action="choose-photo"><span>▧</span><span>Upload a photo</span><span class="photo-spark">✦</span></button>
    ${state.estimating ? '<p class="loading-state"><i class="spinner"></i>Reading your plate…</p>' : ""}
    ${state.error ? `<p class="error-copy">${safe(state.error)}</p><div class="error-actions">${retry}<button class="quiet-link" type="button" data-action="manual-mode">Enter manually</button></div>` : ""}
    ${state.manualMode ? `<p class="small-label">NUTRIENTS</p><div class="nutrient-fields">${nutrientInput("Calories", "calories", 0, "kcal")}${nutrientInput("Protein", "protein", 0, "g")}${nutrientInput("Carbs", "carbs", 0, "g")}${nutrientInput("Fat", "fat", 0, "g")}${nutrientInput("Fiber", "fiber", 0, "g")}${nutrientInput("Added sugar", "sugar", 0, "g")}${nutrientInput("Sodium", "sodium", 0, "mg")}</div><button class="primary-button" type="button" data-action="save-manual">Log meal</button>` : `<button class="primary-button" type="button" data-action="estimate-food" ${text.trim() && !state.estimating ? "" : "hidden"}>Log from description</button>`}
  </div>`;
}

function nutrientInput(label, key, amount, unit) {
  return `<label class="nutrient-input"><span>${label}</span><input type="number" inputmode="decimal" min="0" step="any" data-nutrient="${key}" value="${Number(amount) || 0}"><span>${unit}</span></label>`;
}

function renderProfile() {
  return `<div class="app-mode"><h1 class="view-heading">Profile.</h1><p class="view-note">Your defaults can change as you do.</p><div class="metric-row"><span>FOCUS</span><strong>${safe(state.focus)}</strong></div><div class="metric-row"><span>CALORIES</span><strong>2,200 kcal</strong></div><div class="metric-row"><span>PROTEIN</span><strong>140 g</strong></div><div class="metric-row"><span>STEPS</span><strong>8,000</strong></div><p class="status-message">This browser demo uses sample settings. Connect Apple Health or Calendar in the iPhone app.</p><div class="quick-add-row"><button class="glass-chip" type="button" data-action="show-progress">View progress</button><button class="glass-chip" type="button" data-action="show-tour">Show me around</button></div></div>`;
}

function renderProgress() {
  const balance = getBalance();
  return `<div class="app-mode"><h1 class="view-heading">Progress.</h1><p class="view-note">A calm look back at this demo session.</p><div class="metric-row"><span>BALANCE</span><strong>${balance}% average</strong></div><div class="metric-row"><span>HABITS</span><strong>${state.habits.filter((item) => item.done).length} done</strong></div><div class="metric-row"><span>INTAKE</span><strong>${state.meals.length} meals</strong></div><div class="metric-row"><span>MOVEMENT</span><strong>${state.steps.toLocaleString()} steps</strong></div><p class="status-message">Demo data clears when you start over.</p></div>`;
}

function renderSmartNote() {
  return `<div class="app-mode"><h1 class="view-heading">Write it as it happened.</h1><p class="view-note">A browser-friendly version of Smart Note.</p><textarea id="smart-note" class="food-field" rows="3" placeholder="I had yogurt and berries, then walked home">${safe(state.smartNoteText)}</textarea>
    <button class="primary-button" type="button" data-action="save-smart-note">Sort this note</button>
    ${state.smartNoteMessage ? `<p class="status-message">${safe(state.smartNoteMessage)}</p>` : ""}</div>`;
}

function renderTabBar() {
  const tabs = [["Hub", icons.hub], ["To-Do", icons.todo], ["Movement", icons.move], ["Intake", icons.intake]];
  return `<nav class="tab-bar" aria-label="Main tabs">${tabs.map(([name, symbol]) => `<button class="tab-button" type="button" role="tab" aria-selected="${state.tab === name}" data-action="tab" data-tab="${name}"><span class="tab-symbol">${symbol}</span><span>${name}</span></button>`).join("")}</nav>`;
}

function renderDemoControls() {
  if (state.guidedMode) return `<div class="demo-controls"><span>GUIDED DEMO</span><div class="demo-control-actions"><button class="quiet-link mobile-feedback-entry" type="button" data-action="show-feedback">Help shape Koi →</button><button class="quiet-link" type="button" data-action="exit-guided">Exit guided demo</button></div></div>`;
  return `<div class="demo-controls"><span>DEMO</span><div class="demo-control-actions"><button class="quiet-link mobile-guided-entry" type="button" data-action="start-guided">Guided demo</button><button class="quiet-link" type="button" data-action="show-feedback">Help shape Koi →</button><button class="quiet-link" type="button" data-action="start-fresh">Start fresh</button></div></div>`;
}

function render() {
  renderHeader();
  const isApp = state.stage === "app";
  demoBar.hidden = !isApp;
  demoFooter.hidden = !isApp;
  view.className = `app-view${isApp ? " app-mode" : ""}`;
  tabBar.classList.toggle("visible", isApp && !state.foodOpen && !state.smartNoteOpen);
  renderCaptionPanel();
  if (!isApp) {
    const screens = { respondent: renderRespondentStart, feedback: renderFeedbackForm, thanks: renderThanks, welcome: renderWelcome, connect: renderConnect, focus: renderFocus };
    view.innerHTML = (screens[state.stage] ?? renderRespondentStart)();
  } else {
    let content;
    if (state.smartNoteOpen) content = renderSmartNote();
    else if (state.pondOpen) content = renderPond();
    else if (state.foodOpen) content = renderFoodComposer();
    else {
      const screen = { Hub: renderHub, "To-Do": renderTodo, Movement: renderMovement, Intake: renderIntake, Profile: renderProfile, Progress: renderProgress }[state.tab] ?? renderHub;
      content = screen();
    }
    view.innerHTML = `${renderDemoControls()}${content}${state.smartNoteOpen ? "" : renderCoachCard()}`;
  }
  tabBar.innerHTML = renderTabBar();
  if (state.stage === "app" && !state.foodOpen && !state.smartNoteOpen) {
    const handle = document.createElement("button");
    handle.type = "button";
    handle.className = "smart-handle";
    handle.dataset.action = "smart-note";
    handle.textContent = "Quick note";
    tabBar.prepend(handle);
  }
}

function enterApp() {
  state.stage = "app";
  state.tab = "Hub";
  state.tourVisible = true;
  render();
  requestMorningCoachIfNeeded();
}

function requireRespondentName() {
  const input = document.querySelector("#respondent-first-name");
  const firstName = input?.value.trim().replace(/\s+/g, " ").slice(0, 40) || "";
  if (!firstName) { input?.reportValidity(); return false; }
  respondent.firstName = firstName;
  state.name = firstName;
  return true;
}

function showFeedback() {
  respondentStartedAt = new Date().toISOString();
  respondent.firstName = "";
  respondent.feedbackBusy = false;
  respondent.feedbackError = "";
  state.guidedMode = false;
  state.foodOpen = false;
  state.smartNoteOpen = false;
  state.pondOpen = false;
  state.stage = "respondent";
  render();
}

async function submitFeedback(form) {
  const fields = new FormData(form);
  const answers = {
    wouldUse: fields.get("wouldUse")?.toString() || "",
    wouldPay: fields.get("wouldPay")?.toString() || "",
    dailyUse: fields.get("dailyUse")?.toString().trim() || "",
  };
  const email = fields.get("email")?.toString().trim() || "";
  const button = form.querySelector('button[type="submit"]');
  respondent.feedbackBusy = true;
  button.disabled = true;
  button.textContent = "Sending…";
  respondent.feedbackError = "";
  try {
    const response = await fetch(FEEDBACK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ respondentId, firstName: respondent.firstName, answers, email, startedAt: respondentStartedAt, finishedAt: new Date().toISOString() }),
    });
    if (!response.ok) {
      let detail = "Feedback could not be saved. Please try again.";
      try { detail = (await response.json()).error || detail; } catch { /* Keep a friendly message for an unreadable response. */ }
      throw new Error(detail);
    }
    trackDemoEvent("feedback_submitted");
    state.stage = "thanks";
    render();
  } catch (error) {
    respondent.feedbackError = error.message || "Feedback could not be saved. Please try again.";
    button.disabled = false;
    button.textContent = "Send answers";
    let errorNode = form.querySelector(".feedback-error");
    if (!errorNode) {
      errorNode = document.createElement("p");
      errorNode.className = "feedback-error";
      errorNode.setAttribute("role", "alert");
      form.insertBefore(errorNode, button);
    }
    errorNode.textContent = respondent.feedbackError;
  } finally {
    respondent.feedbackBusy = false;
  }
}

function startFresh() {
  trackDemoEvent("start_fresh");
  state = initialState();
  state.stage = "app";
  state.name = respondent.firstName;
  state.tourVisible = false;
  render();
}

function startGuided() {
  trackDemoEvent("guided_started");
  state = initialState();
  state.stage = "app";
  state.guidedMode = true;
  state.guidedStep = "start";
  state.name = respondent.firstName;
  state.tourVisible = false;
  state.habits = [
    { id: crypto.randomUUID(), title: "Morning water", done: true },
    { id: crypto.randomUUID(), title: "Read 10 pages", done: true },
    { id: crypto.randomUUID(), title: "Walk outside", done: false },
  ];
  state.meals = [{ id: crypto.randomUUID(), description: "Oat bowl with berries", calories: 510, protein: 18, carbs: 75, fat: 14, fiber: 9, sugar: 11, sodium: 160, confidence: .72, source: "sample", imageURL: "" }];
  state.steps = 4_800;
  state.streak = 12;
  state.bestStreak = 18;
  state.sampleSchedule = sampleEventDate().toISOString();
  state.guidedStartBalance = getBalance();
  render();
}

function requestMorningCoachIfNeeded() {
  if (state.guidedMode || respondent.morningCoachRequested) return;
  respondent.morningCoachRequested = true;
  requestCoach("morning");
}

function nutritionTotals() {
  return state.meals.reduce((total, meal) => ({
    calories: total.calories + meal.calories,
    protein: total.protein + meal.protein,
    carbs: total.carbs + meal.carbs,
    fat: total.fat + meal.fat,
    fiber: total.fiber + meal.fiber,
    added_sugar: total.added_sugar + meal.sugar,
    sodium: total.sodium + meal.sodium,
  }), { calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, added_sugar: 0, sodium: 0 });
}

function localCoach(event, context) {
  const protein = context.totals.protein;
  const goal = context.goals.protein;
  if (event === "workout" && protein < goal) {
    return { message: context.pondRank ? `You're ${context.pondRank}. A little more protein supports today's training.` : "Your workout could use a little more protein today.", action: { type: "adjustGoal", nutrient: "protein", delta: 10, why: "Support today's training." } };
  }
  if (event === "meal" && context.pondRank && context.firstCalendarEvent) {
    return { message: `You're ${context.pondRank}. A 3-mile run tomorrow before class would build consistency and help you move up.`, action: { type: "addTodo", title: "3-mile run", dueDate: tomorrowAtSeven().toISOString(), why: "Leave time before your first event." } };
  }
  return { message: "A short walk tomorrow could round out your movement.", action: { type: "addTodo", title: "Take a short walk", dueDate: tomorrowAtSeven().toISOString(), why: "Make a little space for movement." } };
}

async function requestCoach(event) {
  if (state.coachLoading) return;
  state.coachEvent = event;
  const totals = nutritionTotals();
  const context = {
    event,
    today: localISODate(),
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC",
    scores: { habits: Math.round((state.habits.length ? state.habits.filter((item) => item.done).length / state.habits.length : 0) * 100), nutrition: state.meals.length ? Math.round((Math.min(totals.calories / 2200, 1) + Math.min(totals.protein / state.proteinGoalToday, 1) + Math.min(totals.fiber / 30, 1)) / 3 * 100) : 0, exercise: Math.min(100, Math.round(state.steps / 8000 * 60 + (state.didTrain ? 40 : 0))) },
    goals: { calories: 2200, protein: state.proteinGoalToday, fiber: 30, steps: 8000 },
    totals,
    pondRank: coachRank(),
    firstCalendarEvent: state.guidedMode || state.pondViewed ? "Sample schedule: Class at 9:00 AM" : null,
  };
  state.coachLoading = true;
  state.coachError = "";
  render();
  const response = await callAI("coach", "", null, context);
  const fallback = localCoach(event, context);
  const expectedGuidedAction = state.guidedMode && event === "workout" ? "adjustGoal" : state.guidedMode && event === "meal" ? "addTodo" : null;
  const guidedResponseMatches = !expectedGuidedAction || response?.action?.type === expectedGuidedAction && (expectedGuidedAction !== "adjustGoal" || response.action.nutrient === "protein") && (expectedGuidedAction !== "addTodo" || /3-mile run/i.test(response.action.title || ""));
  state.coachSuggestion = response && response.action && guidedResponseMatches ? response : fallback;
  state.coachLoading = false;
  state.coachError = "";
  render();
  if (state.coachSuggestion) trackDemoEvent("coach_shown");
}

function scheduleBeforeSampleEvent() {
  const eventDate = state.guidedMode || state.pondViewed ? new Date(state.sampleSchedule || sampleEventDate()) : null;
  const preferred = tomorrowAtSeven();
  if (!eventDate || !Number.isFinite(eventDate.getTime()) || localISODate(eventDate) !== localISODate(preferred)) return preferred;
  if (preferred.getTime() + 30 * 60_000 <= eventDate.getTime()) return preferred;
  return new Date(eventDate.getTime() - 30 * 60_000);
}

function acceptCoach() {
  const action = state.coachSuggestion?.action;
  if (!action) return;
  trackDemoEvent("coach_accepted");
  if (action.type === "adjustGoal" && action.nutrient === "protein") {
    state.goalDate = new Date().toLocaleDateString("en-CA");
    state.balanceFloor = Math.max(state.balanceFloor || 0, getBalance());
    state.proteinGoalToday += Math.min(500, Math.max(1, Number(action.delta) || 10));
    state.coachSuggestion = null;
    state.coachError = "";
    if (state.guidedMode) { state.guidedStep = "target"; state.tab = "Intake"; }
    render();
    return;
  }
  if (action.type === "addTodo") {
    const dueAt = scheduleBeforeSampleEvent();
    state.tasks.push({ id: crypto.randomUUID(), title: String(action.title || "A little movement").slice(0, 100), done: false, dueAt: dueAt.toISOString() });
    state.coachSuggestion = null;
    state.coachError = "";
    state.tab = "To-Do";
    state.pondOpen = false;
    if (state.guidedMode) state.guidedStep = "todo";
    render();
    return;
  }
  state.coachSuggestion = null;
  render();
}

function updateName() {
  state.name = document.querySelector("#first-name")?.value.trim().slice(0, 28) ?? state.name;
}

function openFood() {
  state.tab = "Intake";
  state.foodOpen = true;
  state.error = "";
  state.foodResult = null;
  state.editingMealID = null;
  state.manualMode = false;
  state.foodText = "";
  state.foodPhoto = null;
  state.foodPreview = "";
  render();
  document.querySelector("#food-description")?.focus({ preventScroll: true });
}

function closeFood() {
  state.foodOpen = false;
  state.foodResult = null;
  state.editingMealID = null;
  state.manualMode = false;
  state.error = "";
  render();
}

function mapEstimate(raw, text = "") {
  return {
    description: raw.description || raw.meal || text.trim() || "Meal",
    calories: Number(raw.calories ?? 0),
    protein: Number(raw.protein_g ?? raw.proteinGrams ?? 0),
    carbs: Number(raw.carbs_g ?? raw.carbohydrateGrams ?? 0),
    fat: Number(raw.fat_g ?? raw.fatGrams ?? 0),
    fiber: Number(raw.fiber_g ?? raw.fiberGrams ?? 0),
    sugar: Number(raw.added_sugar_g ?? raw.addedSugarGrams ?? 0),
    sodium: Number(raw.sodium_mg ?? raw.sodiumMilligrams ?? 0),
    confidence: Math.max(0, Math.min(Number(raw.confidence ?? 0.6), 1)),
  };
}

function friendlyError(status, message = "") {
  if (status === 401) return "Koi couldn't connect to its food service. Try again or enter the numbers yourself.";
  if (status === 413) return "That photo is too large. Try a smaller one or enter the numbers yourself.";
  if (status === 429) return "You've reached today's demo limit. You can still enter the numbers yourself.";
  if (status >= 500) return "Koi's food service is taking a pause. Try again or enter the numbers yourself.";
  if (message.includes("Failed to fetch") || message.includes("NetworkError")) return "Couldn't reach Koi's estimator. Check your connection or enter the numbers yourself.";
  return "Couldn't estimate this meal. Try again or enter the numbers yourself.";
}

async function callAI(task, text, photoData = null, context = null) {
  if (state.estimating || state.importingPlan || state.coachLoading && task !== "coach") return null;
  const busyKey = task === "estimate" ? "estimating" : task === "plan" ? "importingPlan" : "coachLoading";
  const errorKey = task === "estimate" ? "error" : task === "plan" ? "planError" : "coachError";
  state[busyKey] = true;
  state[errorKey] = "";
  render();
  try {
    const payload = { task, ...(task === "coach" ? { context } : { text: text?.trim() || undefined }), image: photoData?.base64, mediaType: photoData ? "image/jpeg" : undefined, deviceId: demoDeviceID };
    const response = await fetch(AI_PROXY_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw Object.assign(new Error(body.error || "request failed"), { status: response.status });
    return body;
  } catch (error) {
    state[errorKey] = friendlyError(error.status ?? 0, error.message ?? "");
    return null;
  } finally {
    state[busyKey] = false;
    render();
  }
}

async function estimateFood() {
  if (!state.foodText.trim() && !state.foodPhoto) return;
  const response = await callAI("estimate", state.foodText, state.foodPhoto);
  if (!response) return;
  const estimate = mapEstimate(response, state.foodText);
  estimate.id = crypto.randomUUID();
  estimate.imageURL = state.foodPreview;
  estimate.source = "ai";
  state.meals.push(estimate);
  trackDemoEvent(state.foodPhoto ? "meal_logged_photo" : "meal_logged_text");
  state.foodResult = estimate;
  state.error = "";
  state.tourVisible = false;
  if (state.guidedMode && state.guidedStep === "photo") {
    state.guidedStep = "balance";
    state.foodOpen = false;
    state.tab = "Hub";
  }
  render();
  if (!state.guidedMode) requestCoach("meal");
}

async function importPlan() {
  state.planText = document.querySelector("#plan-text")?.value ?? state.planText;
  if (!state.planText.trim() && !state.planPhoto) return;
  const response = await callAI("plan", state.planText, state.planPhoto);
  if (!response) return;
  const routine = response.routines?.[0];
  if (!routine?.exercises?.length) {
    state.planError = "Koi couldn't find a routine in that plan. Try a clearer photo or add exercises as text.";
  } else {
    state.planResult = { name: routine.name || "Your routine", exercises: routine.exercises };
    state.planError = "";
  }
  render();
}

async function photoAsJPEG(file) {
  if (!file || !file.type.startsWith("image/")) throw new Error("Choose an image file.");
  if (file.size > 12 * 1024 * 1024) throw new Error("That photo is too large. Choose an image under 12 MB.");
  const image = await createImageBitmap(file);
  const scale = Math.min(1, 1500 / Math.max(image.width, image.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(image.width * scale);
  canvas.height = Math.round(image.height * scale);
  canvas.getContext("2d", { alpha: false }).drawImage(image, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", .78));
  if (!blob) throw new Error("Couldn't prepare that photo. Try another one.");
  const base64 = await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1] || "");
    reader.onerror = () => reject(new Error("Couldn't read that photo. Try another one."));
    reader.readAsDataURL(blob);
  });
  return { name: file.name, base64, blob };
}

async function useSamplePhoto() {
  state.guidedStep = "photo";
  state.tab = "Intake";
  state.foodOpen = true;
  state.foodText = "";
  state.foodResult = null;
  state.error = "";
  state.manualMode = false;
  render();
  try {
    const response = await fetch("assets/sample-protein-bar.png", { cache: "no-cache" });
    if (!response.ok) throw new Error("Couldn't load the sample photo. Try again.");
    const source = await response.blob();
    const file = new File([source], "sample-protein-bar.png", { type: "image/png" });
    state.foodPhoto = await photoAsJPEG(file);
    state.foodPreview = URL.createObjectURL(state.foodPhoto.blob);
    render();
    await estimateFood();
  } catch (error) {
    state.error = friendlyError(0, error.message || "Couldn't prepare that photo.");
    render();
  }
}

function addTodo(title, type) {
  const cleaned = title.trim().slice(0, 100);
  if (!cleaned) return;
  if (type === "habit") state.habits.push({ id: crypto.randomUUID(), title: cleaned, done: false });
  else state.tasks.push({ id: crypto.randomUUID(), title: cleaned, done: false });
  state.tourVisible = false;
  render();
}

function smartNote() {
  const note = state.smartNoteText.trim();
  if (!note) { state.smartNoteMessage = "Write a short note first."; render(); return; }
  const lower = note.toLowerCase();
  if (/\b(ate|eaten|had|meal|breakfast|lunch|dinner|snack|drank|coffee)\b/.test(lower)) {
    state.foodOpen = true;
    state.smartNoteOpen = false;
    state.foodText = note;
    state.foodPhoto = null;
    state.foodResult = null;
    state.error = "";
    render();
    estimateFood();
    return;
  }
  if (/\b(walk|walked|run|ran|workout|lifted|steps|bike|cycled|exercise)\b/.test(lower)) {
    state.steps += /\b(run|ran|workout|lifted)\b/.test(lower) ? 1200 : 700;
    state.smartNoteMessage = "Saved as movement for this demo.";
    state.tourVisible = false;
    render();
    return;
  }
  if (/\b(remind me|need to|don't forget|do this|task)\b/.test(lower)) {
    addTodo(note.replace(/^(remind me to|i need to|don't forget to)\s*/i, ""), "task");
    state.tab = "To-Do";
    state.smartNoteOpen = false;
    render();
    return;
  }
  state.smartNoteMessage = "Saved as a reflection in this demo.";
  render();
}

function saveManualMeal() {
  const description = document.querySelector("#food-description")?.value.trim() || "Meal";
  const values = Object.fromEntries([...document.querySelectorAll("[data-nutrient]")].map((input) => [input.dataset.nutrient, Math.max(0, Number(input.value) || 0)]));
  const estimate = { id: crypto.randomUUID(), description, calories: values.calories, protein: values.protein, carbs: values.carbs, fat: values.fat, fiber: values.fiber, sugar: values.sugar, sodium: values.sodium, confidence: 0, source: "manual", imageURL: state.foodPreview };
  state.meals.push(estimate);
  trackDemoEvent(state.foodPhoto ? "meal_logged_photo" : "meal_logged_text");
  state.foodResult = estimate;
  state.editingMealID = null;
  state.manualMode = false;
  state.error = "";
  state.tourVisible = false;
  render();
  requestCoach("meal");
}

function onClick(event) {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const action = button.dataset.action;

  if (action === "restart" || action === "start-fresh") { startFresh(); return; }
  if (action === "start-guided") { startGuided(); return; }
  if (action === "exit-guided") { state.guidedMode = false; state.guidedStep = "start"; render(); return; }
  if (action === "show-feedback") { showFeedback(); return; }
  if (action === "back-to-koi") { state.stage = "app"; state.tab = "Hub"; render(); return; }
  if (action === "next-person") { window.location.reload(); return; }
  if (action === "next-connect") { updateName(); state.stage = "connect"; render(); return; }
  if (action === "skip-setup") { updateName(); enterApp(); return; }
  if (action === "next-focus") { state.stage = "focus"; render(); return; }
  if (action === "toggle-health") { state.health = !state.health; render(); return; }
  if (action === "toggle-calendar") { state.calendar = !state.calendar; render(); return; }
  if (action === "select-focus") { state.focus = button.dataset.value; render(); return; }
  if (action === "start-demo") { enterApp(); return; }
  if (action === "tab") { state.tab = button.dataset.tab; state.foodOpen = false; state.smartNoteOpen = false; state.pondOpen = false; state.tourVisible = false; render(); return; }
  if (action === "profile") { state.tab = "Profile"; render(); return; }
  if (action === "open-food") { openFood(); return; }
  if (action === "close-food") { closeFood(); return; }
  if (action === "open-pond") { trackDemoEvent("pond_opened"); state.pondOpen = true; state.pondViewed = true; if (!state.sampleSchedule) state.sampleSchedule = sampleEventDate().toISOString(); if (state.guidedMode) state.guidedStep = "pond"; render(); return; }
  if (action === "close-pond") { state.pondOpen = false; render(); return; }
  if (action === "return-from-pond") {
    state.pondOpen = false;
    state.tab = "Hub";
    if (state.guidedMode) { state.guidedStep = "coach"; render(); requestCoach("meal"); }
    else if (["meal", "workout"].includes(state.coachEvent)) { state.coachSuggestion = null; render(); requestCoach(state.coachEvent); }
    else render();
    return;
  }
  if (action === "accept-coach") { acceptCoach(); return; }
  if (action === "dismiss-coach") { state.coachSuggestion = null; state.coachError = ""; if (state.guidedMode) state.guidedMode = false; render(); return; }
  if (action === "retry-coach") { requestCoach(state.coachEvent || "morning"); return; }
  if (action === "estimate-food" || action === "retry-food") { state.foodText = document.querySelector("#food-description")?.value ?? state.foodText; estimateFood(); return; }
  if (action === "choose-photo") { photoInput.removeAttribute("capture"); photoInput.click(); return; }
  if (action === "take-photo") { photoInput.setAttribute("capture", "environment"); photoInput.click(); return; }
  if (action === "use-sample-photo") { useSamplePhoto(); return; }
  if (action === "manual-mode") { state.foodText = document.querySelector("#food-description")?.value ?? state.foodText; state.manualMode = true; state.error = ""; render(); return; }
  if (action === "save-manual") { saveManualMeal(); return; }
  if (action === "toggle-habit") {
    const habit = state.habits.find((item) => item.id === button.dataset.id);
    if (habit) {
      habit.done = !habit.done;
      if (habit.done) { state.tourVisible = false; render(); requestCoach("habit"); }
      else render();
    }
    return;
  }
  if (action === "toggle-task") {
    const task = state.tasks.find((item) => item.id === button.dataset.id);
    if (task) { task.done = !task.done; render(); }
    return;
  }
  if (action === "edit-food") { state.editingMealID = state.foodResult.id; render(); return; }
  if (action === "save-edit") {
    const meal = state.meals.find((item) => item.id === state.editingMealID);
    if (meal) {
      meal.description = document.querySelector("#edit-meal-name")?.value.trim() || meal.description;
      for (const input of document.querySelectorAll("[data-nutrient]")) meal[input.dataset.nutrient] = Math.max(0, Number(input.value) || 0);
      state.foodResult = meal;
    }
    state.editingMealID = null; render(); return;
  }
  if (action === "delete-meal") { state.meals = state.meals.filter((item) => item.id !== state.editingMealID); state.editingMealID = null; state.foodResult = null; render(); return; }
  if (action === "show-all") { state.showAllToday = !state.showAllToday; render(); return; }
  if (action === "cancel-edit") { state.editingMealID = null; render(); return; }
  if (action === "log-another") { state.foodText = ""; state.foodPhoto = null; state.foodPreview = ""; state.foodResult = null; state.error = ""; state.manualMode = false; state.editingMealID = null; render(); return; }
  if (action === "tour") { state.tourVisible = false; state.smartNoteOpen = true; state.smartNoteMessage = "Look around the four tabs, log a sample item, or try a Quick note."; render(); return; }
  if (action === "show-tour") { state.smartNoteOpen = true; state.smartNoteMessage = "Your day comes together across four tabs. Try Intake or Movement."; render(); return; }
  if (action === "show-progress") { state.tab = "Progress"; render(); return; }
  if (action === "smart-note") { state.smartNoteOpen = true; state.smartNoteMessage = ""; state.smartNoteText = ""; render(); return; }
  if (action === "save-smart-note") { state.smartNoteText = document.querySelector("#smart-note")?.value ?? ""; smartNote(); return; }
  if (action === "steps") { state.steps = Math.max(0, state.steps + Number(button.dataset.delta)); state.tourVisible = false; render(); return; }
  if (action === "toggle-workout") {
    const wasTrained = state.didTrain;
    state.didTrain = !state.didTrain;
    state.tourVisible = false;
    if (!wasTrained) {
      if (state.guidedMode) { state.guidedStep = "workout"; state.tab = "Hub"; }
      render();
      requestCoach("workout");
    } else render();
    return;
  }
  if (action === "import-plan") { importPlan(); return; }
  if (action === "pick-plan-photo") { photoInput.dataset.mode = "plan"; photoInput.click(); return; }
}

root.addEventListener("click", onClick);
document.querySelector(".demo-bar").addEventListener("click", onClick);

view.addEventListener("input", (event) => {
  if (event.target.id === "food-description") {
    state.foodText = event.target.value;
    const estimateButton = view.querySelector('[data-action="estimate-food"]');
    if (estimateButton) estimateButton.hidden = !state.foodText.trim() || state.estimating;
  }
  if (event.target.id === "plan-text") state.planText = event.target.value;
  if (event.target.id === "smart-note") state.smartNoteText = event.target.value;
});

view.addEventListener("submit", (event) => {
  if (event.target.id === "respondent-name-form") {
    event.preventDefault();
    if (requireRespondentName()) { state.stage = "feedback"; render(); }
    return;
  }
  if (event.target.id === "feedback-form") {
    event.preventDefault();
    submitFeedback(event.target);
    return;
  }
  const form = event.target.closest("form[data-form]");
  if (!form) return;
  event.preventDefault();
  addTodo(new FormData(form).get("title")?.toString() ?? "", form.dataset.form);
});

photoInput.addEventListener("change", async () => {
  const file = photoInput.files?.[0];
  const mode = photoInput.dataset.mode || "meal";
  photoInput.dataset.mode = "meal";
  photoInput.value = "";
  if (!file) return;
  try {
    const photo = await photoAsJPEG(file);
    if (mode === "plan") {
      state.planPhoto = photo;
      state.planError = "";
      state.tab = "Movement";
      render();
      await importPlan();
    } else {
      state.foodPhoto = photo;
      state.foodPreview = URL.createObjectURL(photo.blob);
      state.error = "";
      state.foodOpen = true;
      state.tab = "Intake";
      render();
      if (!state.foodText.trim()) await estimateFood();
    }
  } catch (error) {
    state.error = friendlyError(0, error.message);
    state.foodOpen = true;
    render();
  }
});

function setClock() {
  document.querySelector("#clock").textContent = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(new Date());
}

setClock();
setInterval(setClock, 30_000);
render();
trackDemoEvent("visit");
requestMorningCoachIfNeeded();
