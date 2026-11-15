const FEEDBACK_URL = "https://koi-demo-api.vercel.app/api/demo-feedback";
const EVENT_URL = "https://koi-demo-api.vercel.app/api/demo-event";
const testMode = new URLSearchParams(location.search).get("test") === "1";
const respondentId = crypto.randomUUID();
const startedAt = new Date().toISOString();
const steps = [
  { image: "01-hub.png", title: "One score for your day", copy: "Habits, food and movement come together in one calm view. The highlight marks Nutrition, one of the three pillars.", hot: [35, 46], tap: "Nutrition pillar" },
  { image: "02-workout-logged.png", title: "Movement counts", copy: "The first set is logged. Each workout adds to movement alongside your daily steps.", hot: [50, 85], tap: "Log the next set" },
  { image: "03-coach.png", title: "Pillars talk to each other", copy: "After the workout, Koi suggests 10 g more protein today. The next screen shows the adjusted Intake target.", hot: [18, 81], tap: "Accept the protein suggestion" },
  { image: "04-intake-adjusted.png", title: "Your target adapts to training", copy: "The protein target is now 150 g for today. Logging food closes the gap, while Balance stays protected.", hot: [82, 83], tap: "Protein target, 150 grams" },
  { image: "05-photo-result.png", title: "AI reads a photo", copy: "A protein bar photo becomes a meal estimate with calories and macros. Fix the numbers if anything looks off.", hot: [27, 61], tap: "Fix meal numbers" },
  { image: "06-hub-after.png", title: "One score, all three pillars", copy: "The meal and workout now count in today's Balance. It rises from 77% to 90% as your day comes together.", hot: [77, 26], tap: "90 percent Balance" },
  { image: "07-pond.png", title: "Friends keep you consistent", copy: "The sample pond has five friends in a sprint. Maya is currently 3rd of 5.", hot: [55, 71], tap: "Maya's third-place row" },
  { image: "08-run-suggestion.png", title: "Koi plans around your schedule", copy: "The sample schedule has class at 9 AM. Koi suggests a 3-mile run before class; the final screen shows it in To-Do.", hot: [18, 81], tap: "Accept the run suggestion" },
  { image: "09-todo-run.png", title: "A next step, already planned", copy: "The 3-mile run is in To-Do for tomorrow morning, before class.", hot: [31, 48], tap: "3-mile run task" },
];
const copy = document.querySelector("#tour-copy");
const screen = document.querySelector("#tour-screen");
const hotspot = document.querySelector("#hotspot");
const layout = document.querySelector("#tour-layout");
const liveLink = document.querySelector("#live-link");
let index = 0;
let surveyStage = "";
let firstName = "";
let feedbackError = "";
let busy = false;

function track(event) {
  fetch(EVENT_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ respondentId, event, timestamp: new Date().toISOString(), test: testMode }),
    keepalive: true,
  }).catch(() => {});
}
track("visit");
if (testMode) {
  const testLiveURL = new URL("app/", location.href);
  testLiveURL.searchParams.set("test", "1");
  liveLink.href = testLiveURL.href;
}

function showTourStep() {
  surveyStage = "";
  layout.className = "tour-layout";
  layout.innerHTML = `<div class="tour-copy" id="tour-copy"></div><div class="phone-wrap"><div class="phone-frame"><img class="tour-screen" id="tour-screen" alt="Real Koi iPhone app screen"><button class="hotspot" id="hotspot" type="button" aria-label="Continue tour"><span class="hotspot-ring"></span><span class="hotspot-arrow">↗</span></button></div></div>`;
  const current = steps[index];
  const copyNode = document.querySelector("#tour-copy");
  const imageNode = document.querySelector("#tour-screen");
  const hotspotNode = document.querySelector("#hotspot");
  imageNode.src = `assets/tour/${current.image}`;
  imageNode.alt = `${current.title} — Koi iPhone app screenshot`;
  hotspotNode.style.left = `${current.hot[0]}%`;
  hotspotNode.style.top = `${current.hot[1]}%`;
  hotspotNode.setAttribute("aria-label", current.tap);
  hotspotNode.addEventListener("click", next);
  copyNode.innerHTML = `<p class="step-kicker">KOI · DAILY BALANCE</p><h1>${current.title}</h1><p>${current.copy}</p><div class="progress-line" aria-label="Tour progress"><i style="width:${((index + 1) / steps.length) * 100}%"></i></div><div class="step-count">${index + 1} of ${steps.length}</div><div class="tour-controls"><button class="nav-button" type="button" data-back aria-label="Previous step" ${index === 0 ? "disabled" : ""}>←</button><button class="nav-button" type="button" data-next aria-label="Next step">→</button><span class="nav-hint">Use the highlighted spot,<br>or your arrow keys.</span></div>`;
  copyNode.querySelector("[data-back]").addEventListener("click", previous);
  copyNode.querySelector("[data-next]").addEventListener("click", next);
  document.querySelector(".tour-footer").innerHTML = `<span>Real app screens · sample data</span><span>Tap the highlighted area or use your arrow keys.</span>`;
  track(`tour_step_${index + 1}`);
}

function previous() { if (index > 0) { index -= 1; showTourStep(); } }
function next() {
  if (index < steps.length - 1) { index += 1; showTourStep(); return; }
  track("tour_completed");
  surveyStage = "name";
  showSurvey();
}

function privacy() {
  return "Student project built at the Cal Poly hackathon. We only keep your first name and answers (plus email if you add it).";
}
function showSurvey() {
  layout.className = "survey-layout";
  if (surveyStage === "name") {
    layout.innerHTML = `<p class="step-kicker">A QUICK QUESTIONNAIRE</p><h1>Your first name</h1><p>Thanks for taking a look at Koi. Your feedback helps us make it better.</p><form id="name-form"><label for="first-name">FIRST NAME</label><input id="first-name" name="firstName" autocomplete="given-name" maxlength="40" required placeholder="First name"><p class="privacy-note">${privacy()}</p><div class="survey-actions"><button class="primary-button" type="submit">Continue</button></div></form>`;
    document.querySelector("#name-form").addEventListener("submit", (event) => {
      event.preventDefault();
      firstName = new FormData(event.currentTarget).get("firstName").toString().trim().replace(/\s+/g, " ").slice(0, 40);
      if (!firstName) return;
      surveyStage = "answers";
      showSurvey();
    });
  } else if (surveyStage === "answers") {
    const group = (key, title) => `<fieldset style="border:0;padding:0;margin:20px 0"><legend style="font-size:13px;margin-bottom:10px">${title}</legend><div class="choice-row">${["Yes", "Maybe", "No"].map((answer) => `<label><input type="radio" name="${key}" value="${answer}" required><span>${answer}</span></label>`).join("")}</div></fieldset>`;
    layout.innerHTML = `<p class="step-kicker">YOUR THOUGHTS</p><h1>A few quick questions.</h1><form id="feedback-form">${group("wouldUse", "Would you use Koi?")}${group("wouldPay", "Would you pay $2.99/month for the AI coach?")}<label for="daily-use">What would make you use it every day?</label><input id="daily-use" name="dailyUse" maxlength="240" placeholder="One line, optional"><label for="email">Email, if you want Koi when it launches</label><input id="email" name="email" type="email" maxlength="254" autocomplete="email" placeholder="Optional"><p class="privacy-note">${privacy()}</p>${feedbackError ? `<p class="survey-error" role="alert">${feedbackError}</p>` : ""}<div class="survey-actions"><button class="primary-button" type="submit" ${busy ? "disabled" : ""}>${busy ? "Sending…" : "Submit"}</button><button class="quiet-button" type="button" id="back-to-name">Back</button></div></form>`;
    document.querySelector("#feedback-form").addEventListener("submit", submitSurvey);
    document.querySelector("#back-to-name").addEventListener("click", () => { surveyStage = "name"; showSurvey(); });
  } else {
    const liveHref = testMode ? "app/?test=1" : "app/";
    layout.innerHTML = `<p class="step-kicker">RECEIVED</p><h1>Thanks, ${escapeHTML(firstName)}!</h1><p>Your note helps shape what Koi becomes.</p><div class="thanks-actions"><button class="primary-button" id="next-person" type="button">Next person</button><a class="live-link" href="${liveHref}" id="thanks-live">Try the live version →</a></div>`;
    document.querySelector("#next-person").addEventListener("click", () => window.location.reload());
    document.querySelector("#thanks-live").addEventListener("click", () => track("live_opened"));
  }
  document.querySelector(".tour-footer").textContent = "";
}

function escapeHTML(value) { return String(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]); }
async function submitSurvey(event) {
  event.preventDefault();
  if (busy) return;
  const form = event.currentTarget;
  const fields = new FormData(form);
  busy = true;
  feedbackError = "";
  const submitButton = form.querySelector('button[type="submit"]');
  submitButton.disabled = true;
  submitButton.textContent = "Sending…";
  try {
    const response = await fetch(FEEDBACK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        respondentId,
        firstName,
        answers: { wouldUse: fields.get("wouldUse"), wouldPay: fields.get("wouldPay"), dailyUse: fields.get("dailyUse")?.toString().trim() || "" },
        email: fields.get("email")?.toString().trim() || "",
        startedAt,
        finishedAt: new Date().toISOString(),
        test: testMode,
      }),
    });
    if (!response.ok) {
      let message = "Feedback could not be saved. Please try again.";
      try { message = (await response.json()).error || message; } catch { /* Keep the friendly fallback. */ }
      throw new Error(message);
    }
    track("survey_submitted");
    surveyStage = "thanks";
    showSurvey();
  } catch (error) {
    busy = false;
    feedbackError = error.message || "Feedback could not be saved. Please try again.";
    submitButton.disabled = false;
    submitButton.textContent = "Submit";
    const notice = document.createElement("p");
    notice.className = "survey-error";
    notice.setAttribute("role", "alert");
    notice.textContent = feedbackError;
    form.querySelector(".survey-actions").before(notice);
  }
}

liveLink.addEventListener("click", () => track("live_opened"));
document.addEventListener("keydown", (event) => {
  if (surveyStage) return;
  if (event.key === "ArrowRight") next();
  if (event.key === "ArrowLeft") previous();
});
showTourStep();
