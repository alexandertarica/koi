const AI_PROXY_URL = "https://koi-sand.vercel.app/api/demo-ai";
const root = document.querySelector("#app-root");
const header = document.querySelector("#app-header");
const view = document.querySelector("#app-view");
const tabBar = document.querySelector("#tab-bar-wrap");
const photoInput = document.querySelector("#photo-input");

const initialState = () => ({
  stage: "welcome",
  name: "",
  focus: "balanced",
  health: false,
  calendar: false,
  tab: "Hub",
  tourVisible: true,
  meals: [],
  tasks: [],
  habits: [],
  steps: 0,
  didTrain: false,
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

function loadDemoState() {
  try {
    const saved = JSON.parse(localStorage.getItem("koi.browser-demo-state") || "null");
    if (!saved || typeof saved !== "object") return initialState();
    return {
      ...initialState(),
      stage: saved.stage === "app" ? "app" : "welcome",
      name: typeof saved.name === "string" ? saved.name.slice(0, 28) : "",
      focus: ["balanced", "habits", "nutrition", "exercise"].includes(saved.focus) ? saved.focus : "balanced",
      tab: ["Hub", "To-Do", "Movement", "Intake", "Profile", "Progress"].includes(saved.tab) ? saved.tab : "Hub",
      tourVisible: saved.tourVisible !== false,
      meals: Array.isArray(saved.meals) ? saved.meals : [],
      tasks: Array.isArray(saved.tasks) ? saved.tasks : [],
      habits: Array.isArray(saved.habits) ? saved.habits : [],
      steps: Math.max(0, Number(saved.steps) || 0),
      didTrain: saved.didTrain === true,
      health: saved.health === true,
      calendar: saved.calendar === true,
    };
  } catch {
    return initialState();
  }
}

let state = loadDemoState();
let demoDeviceID = localStorage.getItem("koi.browser-demo-id");
if (!demoDeviceID) {
  demoDeviceID = crypto.randomUUID();
  localStorage.setItem("koi.browser-demo-id", demoDeviceID);
}

const icons = {
  day: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="4" width="17" height="16" rx="2.2"/><path d="M7.5 8h.1M12 8h.1M16.5 8h.1M7.5 12h.1M12 12h.1M16.5 12h.1M7.5 16h.1M12 16h.1" stroke-width="2.3"/></svg>',
  camera: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 7.5h4l1.7-2h6.6l1.7 2h4v11H3z"/><circle cx="12" cy="13" r="3.5"/></svg>',
  next: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9.5"/><path d="M7.5 12h9M12.5 8l4 4-4 4"/></svg>',
};

function safe(value = "") {
  return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
}

function dateLabel() {
  return new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" }).format(new Date()).toUpperCase();
}

function getBalance() {
  const habit = state.habits.length ? state.habits.filter((item) => item.done).length / state.habits.length : 0;
  const nutrition = state.meals.length ? Math.min(state.meals.reduce((total, meal) => total + meal.calories, 0) / 2200, 1) : 0;
  const movement = Math.min(state.steps / 8000, 1) * .6 + (state.didTrain ? .4 : 0);
  const weights = state.focus === "habits" ? [.5, .25, .25] : state.focus === "nutrition" ? [.25, .5, .25] : state.focus === "exercise" ? [.25, .25, .5] : [1 / 3, 1 / 3, 1 / 3];
  return Math.round((habit * weights[0] + nutrition * weights[1] + movement * weights[2]) * 100);
}

function renderHeader() {
  if (state.stage !== "app") {
    const title = state.stage === "welcome" ? "WELCOME" : state.stage === "connect" ? "CONNECT" : "FOCUS";
    header.innerHTML = `<div class="header-row"><img class="wordmark" src="assets/wordmark.png" alt="Koi"><span class="header-section">${title}</span></div>`;
    return;
  }

  const section = state.foodOpen ? "Log food" : "";
  const right = state.foodOpen
    ? '<button class="close-screen" type="button" data-action="close-food" aria-label="Close meal composer">×</button>'
    : '<button class="close-screen" type="button" data-action="profile" aria-label="Open profile">◯</button>';
  header.innerHTML = `<div class="header-row"><img class="wordmark" src="assets/wordmark.png" alt="Koi">${right}</div>
    <div class="date-label">${dateLabel()}</div>${section ? `<h1 class="screen-title">${section}</h1>` : ""}`;
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
  const nutritionPct = state.meals.length ? Math.min(Math.round(state.meals.reduce((total, meal) => total + meal.calories, 0) / 2200 * 100), 100) : 0;
  const exercisePct = Math.min(Math.round(state.steps / 8000 * 100 + (state.didTrain ? 30 : 0)), 100);
  const greeting = new Date().getHours() >= 22 || new Date().getHours() < 5 ? "Still water" : new Date().getHours() < 12 ? "Good morning" : new Date().getHours() < 18 ? "Good afternoon" : "Good evening";
  const name = state.name ? `, ${safe(state.name)}` : "";
  const items = [
    ...state.habits.map((item) => `<div class="demo-habit"><input type="checkbox" data-action="toggle-habit" data-id="${item.id}" ${item.done ? "checked" : ""}><span>${safe(item.title)}</span><span class="task-state">HABIT</span></div>`),
    ...state.tasks.map((item) => `<div class="demo-task"><input type="checkbox" data-action="toggle-task" data-id="${item.id}" ${item.done ? "checked" : ""}><span>${safe(item.title)}</span><span class="task-state">TO-DO</span></div>`),
  ].slice(0, 2).join("");
  return `<div class="app-mode">
    <h1 class="hub-greeting">${greeting}${name}.</h1>
    <div class="hub-layout">
      <svg class="hub-arc" viewBox="0 0 275 390" preserveAspectRatio="none" aria-hidden="true">
        <path class="track" d="M 1 14 A 188 188 0 0 1 1 390"/>
        <path class="progress" d="M 1 14 A 188 188 0 0 1 1 390" pathLength="100" style="stroke-dasharray:${score} 100"/>
      </svg>
      <div class="pillar-label habits"><span>${habitPct}%</span>HABITS ›</div>
      <div class="pillar-label nutrition"><span>${nutritionPct}%</span>NUTRITION ›</div>
      <div class="pillar-label exercise"><span>${exercisePct}%</span>EXERCISE ›</div>
      <div class="score-block"><div class="score-value">${score}<span>%</span></div><div class="score-label">BALANCE</div></div>
      <div class="trend-chip">↘ 0 vs last week</div>
      <div class="streak-block"><img class="streak-flame" src="assets/flame.svg" alt=""><span class="streak-count">0</span><span class="streak-label">DAY STREAK</span><span class="streak-best">best 0</span></div>
      <div class="trend-line"></div>
    </div>
    <div class="today-block">
      <div class="section-row"><span>TODAY</span>${state.habits.length + state.tasks.length > 2 ? `<span class="more">+${state.habits.length + state.tasks.length - 2} more</span>` : ""}</div>
      ${items || '<p class="empty-copy">Your day is open. Choose one small thing to begin.</p>'}
      <button class="tour-chip" type="button" data-action="tour" ${state.tourVisible ? "" : "hidden"}>◎ Show me around <span aria-hidden="true">×</span></button>
    </div>
    <div class="quick-add-row"><button class="glass-chip" type="button" data-action="tab" data-tab="To-Do">+ Habit</button><button class="glass-chip" type="button" data-action="tab" data-tab="To-Do">+ To-do</button><button class="glass-chip" type="button" data-action="tab" data-tab="Intake">Log food</button></div>
  </div>`;
}

function renderTodo() {
  const habits = state.habits.map((item) => `<div class="demo-habit"><input type="checkbox" data-action="toggle-habit" data-id="${item.id}" ${item.done ? "checked" : ""}><span>${safe(item.title)}</span><span class="task-state">${item.done ? "DONE" : "DAILY"}</span></div>`).join("");
  const tasks = state.tasks.map((item) => `<div class="demo-task"><input type="checkbox" data-action="toggle-task" data-id="${item.id}" ${item.done ? "checked" : ""}><span>${safe(item.title)}</span><span class="task-state">${item.done ? "DONE" : "TO-DO"}</span></div>`).join("");
  return `<div class="app-mode"><h1 class="view-heading">Practice.</h1><p class="view-note">A little room for what matters.</p>
    <p class="small-label">HABITS</p>${habits || '<p class="empty-copy">Your habits will settle here.</p>'}
    <form class="task-form" data-form="habit"><input name="title" maxlength="80" placeholder="A habit to begin" aria-label="A habit to begin"><button type="submit">Add</button></form>
    <p class="small-label">TO-DOS</p>${tasks || '<p class="empty-copy">Your list is clear.</p>'}
    <form class="task-form" data-form="task"><input name="title" maxlength="100" placeholder="What is next?" aria-label="What is next?"><button type="submit">Add</button></form>
  </div>`;
}

function renderMovement() {
  const routine = state.planResult ? `<div class="result-card"><p class="small-label">PLAN READY</p><h2 class="view-heading">${safe(state.planResult.name)}</h2>${state.planResult.exercises.map((item) => `<div class="nutrient-line"><span>${safe(item.name)}</span><span>${item.sets} × ${item.reps}</span></div>`).join("")}</div>` : "";
  return `<div class="app-mode"><h1 class="view-heading">Move with intention.</h1><p class="view-note">Small steps count.</p>
    <div class="metric-row"><span>STEPS TODAY</span><strong>${state.steps.toLocaleString()}</strong></div>
    <div class="quick-add-row"><button class="glass-chip" type="button" data-action="steps" data-delta="-500">− 500</button><button class="glass-chip" type="button" data-action="steps" data-delta="500">+ 500 steps</button></div>
    <div class="metric-row"><span>WORKOUT</span><strong>${state.didTrain ? "Logged" : "Open"}</strong></div>
    <button class="quiet-link" type="button" data-action="toggle-workout">${state.didTrain ? "Undo workout" : "Log a workout"}</button>
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
  return `<div class="app-mode"><div class="result-top"><div><h1 class="view-heading">Nutrition.</h1><p class="view-note">A steady picture of the day.</p></div><button class="glass-chip" type="button" data-action="open-food">LOG${state.meals.length ? ` · ${state.meals.length} logged` : ""}</button></div>
    <div class="metric-row"><span>CALORIES</span><strong>${Math.round(totals.calories).toLocaleString()} <small>of 2,200</small></strong></div>
    <div class="nutrient-list"><div class="nutrient-line"><span>Protein</span><span>${Math.round(totals.protein)} g</span></div><div class="nutrient-line"><span>Carbs</span><span>${Math.round(totals.carbs)} g</span></div><div class="nutrient-line"><span>Fat</span><span>${Math.round(totals.fat)} g</span></div><div class="nutrient-line"><span>Fiber</span><span>${Math.round(totals.fiber)} g</span></div><div class="nutrient-line"><span>Added sugar</span><span>${Math.round(totals.sugar)} g</span></div><div class="nutrient-line"><span>Sodium</span><span>${Math.round(totals.sodium)} mg</span></div></div>
    <p class="small-label">TODAY</p>${mealRows || '<p class="empty-copy">Your meals will settle here.</p>'}<button class="primary-button" type="button" data-action="open-food">Log food</button>
  </div>`;
}

function renderFoodComposer(totals = null) {
  if (!totals) totals = state.meals.reduce((all, meal) => ({ calories: all.calories + meal.calories }), { calories: 0 });
  if (state.foodResult && !state.manualMode && state.editingMealID === null) {
    const result = state.foodResult;
    return `<div class="app-mode">
      <div class="result-top"><span class="result-kcal">~${Math.round(result.calories)} kcal</span><span class="result-sure">${Math.round(result.confidence * 100)}% sure</span></div>
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
      <button class="primary-button" type="button" data-action="save-edit">Save</button><button class="quiet-link" type="button" data-action="cancel-edit">Cancel</button>
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
  const tabs = [["Hub", "⬡"], ["To-Do", "☷"], ["Movement", "♧"], ["Intake", "⌁"]];
  return `<nav class="tab-bar" aria-label="Main tabs">${tabs.map(([name, symbol]) => `<button class="tab-button" type="button" role="tab" aria-selected="${state.tab === name}" data-action="tab" data-tab="${name}"><span class="tab-symbol">${symbol}</span><span>${name}</span></button>`).join("")}</nav>`;
}

function render() {
  try {
    localStorage.setItem("koi.browser-demo-state", JSON.stringify({
      stage: state.stage, name: state.name, focus: state.focus, tab: state.tab,
      tourVisible: state.tourVisible, meals: state.meals.map(({ imageURL, ...meal }) => meal),
      tasks: state.tasks, habits: state.habits, steps: state.steps, didTrain: state.didTrain,
      health: state.health, calendar: state.calendar,
    }));
  } catch { /* Storage may be unavailable in private browsing; the demo still works. */ }
  renderHeader();
  const isApp = state.stage === "app";
  view.className = `app-view${isApp ? " app-mode" : ""}`;
  tabBar.classList.toggle("visible", isApp && !state.foodOpen && !state.smartNoteOpen);
  if (!isApp) {
    view.innerHTML = state.stage === "welcome" ? renderWelcome() : state.stage === "connect" ? renderConnect() : renderFocus();
  } else if (state.smartNoteOpen) {
    view.innerHTML = renderSmartNote();
  } else if (state.foodOpen) {
    view.innerHTML = renderFoodComposer();
  } else {
    const screen = { Hub: renderHub, "To-Do": renderTodo, Movement: renderMovement, Intake: renderIntake, Profile: renderProfile, Progress: renderProgress }[state.tab] ?? renderHub;
    view.innerHTML = screen();
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

async function callAI(task, text, photoData = null) {
  if (state.estimating || state.importingPlan) return null;
  const busyKey = task === "estimate" ? "estimating" : "importingPlan";
  const errorKey = task === "estimate" ? "error" : "planError";
  state[busyKey] = true;
  state[errorKey] = "";
  render();
  try {
    const payload = { task, text: text?.trim() || undefined, image: photoData?.base64, mediaType: photoData ? "image/jpeg" : undefined, deviceId: demoDeviceID };
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
  state.meals.push(estimate);
  state.foodResult = estimate;
  state.error = "";
  state.tourVisible = false;
  render();
}

async function importPlan() {
  state.planText = document.querySelector("#plan-text")?.value ?? state.planText;
  if (!state.planText.trim() && !state.planPhoto) return;
  const response = await callAI("workout-import", state.planText, state.planPhoto);
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
  const estimate = { id: crypto.randomUUID(), description, calories: values.calories, protein: values.protein, carbs: values.carbs, fat: values.fat, fiber: values.fiber, sugar: values.sugar, sodium: values.sodium, confidence: 0, imageURL: state.foodPreview };
  state.meals.push(estimate);
  state.foodResult = estimate;
  state.editingMealID = null;
  state.manualMode = false;
  state.error = "";
  state.tourVisible = false;
  render();
}

function onClick(event) {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const action = button.dataset.action;

  if (action === "restart") { localStorage.removeItem("koi.browser-demo-state"); state = initialState(); render(); return; }
  if (action === "next-connect") { updateName(); state.stage = "connect"; render(); return; }
  if (action === "skip-setup") { updateName(); enterApp(); return; }
  if (action === "next-focus") { state.stage = "focus"; render(); return; }
  if (action === "toggle-health") { state.health = !state.health; render(); return; }
  if (action === "toggle-calendar") { state.calendar = !state.calendar; render(); return; }
  if (action === "select-focus") { state.focus = button.dataset.value; render(); return; }
  if (action === "start-demo") { enterApp(); return; }
  if (action === "tab") { state.tab = button.dataset.tab; state.foodOpen = false; state.smartNoteOpen = false; state.tourVisible = false; render(); return; }
  if (action === "profile") { state.tab = "Profile"; render(); return; }
  if (action === "open-food") { openFood(); return; }
  if (action === "close-food") { closeFood(); return; }
  if (action === "estimate-food" || action === "retry-food") { state.foodText = document.querySelector("#food-description")?.value ?? state.foodText; estimateFood(); return; }
  if (action === "choose-photo") { photoInput.removeAttribute("capture"); photoInput.click(); return; }
  if (action === "take-photo") { photoInput.setAttribute("capture", "environment"); photoInput.click(); return; }
  if (action === "manual-mode") { state.foodText = document.querySelector("#food-description")?.value ?? state.foodText; state.manualMode = true; state.error = ""; render(); return; }
  if (action === "save-manual") { saveManualMeal(); return; }
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
  if (action === "cancel-edit") { state.editingMealID = null; render(); return; }
  if (action === "log-another") { state.foodText = ""; state.foodPhoto = null; state.foodPreview = ""; state.foodResult = null; state.error = ""; state.manualMode = false; state.editingMealID = null; render(); return; }
  if (action === "tour") { state.tourVisible = false; state.smartNoteOpen = true; state.smartNoteMessage = "Look around the four tabs, log a sample item, or try a Quick note."; render(); return; }
  if (action === "show-tour") { state.smartNoteOpen = true; state.smartNoteMessage = "Your day comes together across four tabs. Try Intake or Movement."; render(); return; }
  if (action === "show-progress") { state.tab = "Progress"; render(); return; }
  if (action === "smart-note") { state.smartNoteOpen = true; state.smartNoteMessage = ""; state.smartNoteText = ""; render(); return; }
  if (action === "save-smart-note") { state.smartNoteText = document.querySelector("#smart-note")?.value ?? ""; smartNote(); return; }
  if (action === "steps") { state.steps = Math.max(0, state.steps + Number(button.dataset.delta)); state.tourVisible = false; render(); return; }
  if (action === "toggle-workout") { state.didTrain = !state.didTrain; state.tourVisible = false; render(); return; }
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
