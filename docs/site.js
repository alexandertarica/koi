const routes = new Map([
  ["home", document.querySelector("#home-view")],
  ["tour", document.querySelector("#tour-view")],
  ["demo", document.querySelector("#demo-view")],
]);

const tourSteps = [
  {
    image: "01-hub.webp",
    title: "One score for your day",
    copy: "Habits, food and movement come together in one view. Jasmine starts at 48% Balance, with Exercise at 25%.",
    alt: "Real Koi Hub screenshot: Jasmine at 48 percent Balance, with the Go to pond chip below BALANCE and no trend pill.",
  },
  {
    image: "02-workout.webp",
    title: "Log a workout",
    copy: "A workout adds to Exercise alongside daily steps. In this stage, Balance moves from 48% to 61%.",
    alt: "Real Koi workout screen with a strength set ready to log.",
  },
  {
    image: "03-coach.webp",
    title: "The pillars talk to each other",
    copy: "After training, Koi Coach suggests adding 10 g of protein to today's goal to support recovery.",
    alt: "Real Koi Coach screenshot suggesting 10 grams more protein after a workout.",
  },
  {
    image: "04-photo-estimate.webp",
    title: "Log food from a photo",
    copy: "The photo flow estimates a protein bar at about 150 kcal and 28 g of protein, ready for review.",
    alt: "Real Koi food estimate screen showing a protein bar detected from a photo.",
  },
  {
    image: "05-pond.webp",
    title: "A little company helps",
    copy: "The sample Koi Pond brings five friends together around daily Balance. Jasmine is in third place.",
    alt: "Real Koi Pond screenshot showing five sample friends and Jasmine in third place.",
  },
  {
    image: "06-todo-important.webp",
    title: "A next step, already planned",
    copy: "The suggested run lands in the Important area of To-Do, before the next calendar event.",
    alt: "Real Koi To-Do screenshot showing the suggested run in the Important quadrant.",
  },
];

const tourState = {
  index: 0,
  pointerStart: null,
};

const tourImage = document.querySelector("#tour-image");
const tourDevice = document.querySelector(".tour-device-wrap");
const tourCopy = document.querySelector("#tour-copy-inner");
const tourCount = document.querySelector("#tour-count");
const tourTitle = document.querySelector("#tour-step-title");
const tourText = document.querySelector("#tour-step-copy");
const tourDots = document.querySelector("#tour-dots");
const tourBack = document.querySelector("#tour-back");
const tourNext = document.querySelector("#tour-next");
const tourEnd = document.querySelector("#tour-end");

function currentRoute() {
  const requested = location.hash.slice(1).toLowerCase();
  return routes.has(requested) ? requested : "home";
}

function renderRoute() {
  const activeRoute = currentRoute();
  for (const [name, view] of routes) {
    view.hidden = name !== activeRoute;
  }
  document.querySelectorAll("[data-route-link]").forEach((link) => {
    if (link.dataset.routeLink === activeRoute) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  });
  document.body.dataset.route = activeRoute;
  if (activeRoute === "tour") renderTourStep(tourState.index, false);
  window.scrollTo({ top: 0, behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
}

function makeTourDots() {
  tourDots.replaceChildren(...tourSteps.map((step, index) => {
    const dot = document.createElement("button");
    dot.className = "tour-dot";
    dot.type = "button";
    dot.setAttribute("aria-label", `Go to tour step ${index + 1}: ${step.title}`);
    dot.addEventListener("click", () => renderTourStep(index));
    return dot;
  }));
}

function renderTourStep(nextIndex, animate = true) {
  tourState.index = Math.max(0, Math.min(tourSteps.length - 1, nextIndex));
  const step = tourSteps[tourState.index];
  const dots = [...tourDots.children];
  dots.forEach((dot, index) => {
    if (index === tourState.index) dot.setAttribute("aria-current", "step");
    else dot.removeAttribute("aria-current");
  });

  tourCount.textContent = `${String(tourState.index + 1).padStart(2, "0")} / ${String(tourSteps.length).padStart(2, "0")}`;
  tourTitle.textContent = step.title;
  tourText.textContent = step.copy;
  tourImage.alt = step.alt;
  tourImage.loading = tourState.index === 0 ? "eager" : "lazy";
  tourImage.src = `assets/shots/${step.image}`;

  tourCopy.classList.toggle("is-entering", animate);
  tourDevice.classList.toggle("is-entering", animate);
  if (animate && !window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    window.setTimeout(() => {
      tourCopy.classList.remove("is-entering");
      tourDevice.classList.remove("is-entering");
    }, 80);
  } else {
    tourCopy.classList.remove("is-entering");
    tourDevice.classList.remove("is-entering");
  }

  tourBack.disabled = tourState.index === 0;
  const isLast = tourState.index === tourSteps.length - 1;
  tourNext.hidden = isLast;
  tourEnd.hidden = !isLast;

  const next = tourSteps[tourState.index + 1];
  if (next) {
    const preload = new Image();
    preload.src = `assets/shots/${next.image}`;
  }
}

function nextTourStep() {
  if (tourState.index < tourSteps.length - 1) renderTourStep(tourState.index + 1);
}

function previousTourStep() {
  if (tourState.index > 0) renderTourStep(tourState.index - 1);
}

document.querySelectorAll("a[href='#tour']").forEach((link) => {
  link.addEventListener("click", () => { tourState.index = 0; });
});
tourBack.addEventListener("click", previousTourStep);
tourNext.addEventListener("click", nextTourStep);
document.querySelector("#tour-again").addEventListener("click", () => {
  tourState.index = 0;
  renderTourStep(0, false);
  if (location.hash !== "#tour") location.hash = "tour";
  else window.scrollTo({ top: 0, behavior: "smooth" });
});

tourDevice.addEventListener("pointerdown", (event) => {
  if (event.pointerType === "mouse") return;
  tourState.pointerStart = { x: event.clientX, y: event.clientY };
});
tourDevice.addEventListener("pointerup", (event) => {
  const start = tourState.pointerStart;
  tourState.pointerStart = null;
  if (!start) return;
  const deltaX = event.clientX - start.x;
  const deltaY = event.clientY - start.y;
  if (Math.abs(deltaX) < 44 || Math.abs(deltaX) < Math.abs(deltaY)) return;
  if (deltaX < 0) nextTourStep();
  else previousTourStep();
});

document.addEventListener("keydown", (event) => {
  if (currentRoute() !== "tour" || event.altKey || event.ctrlKey || event.metaKey) return;
  if (event.key === "ArrowRight") nextTourStep();
  if (event.key === "ArrowLeft") previousTourStep();
});

window.addEventListener("hashchange", renderRoute);
makeTourDots();
renderTourStep(0, false);
renderRoute();

function animateBalance() {
  const target = document.querySelector(".caption-mark");
  if (!target) return;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduceMotion) {
    target.textContent = "48 → 61 → 67";
    return;
  }
  const start = performance.now();
  const duration = 1500;
  const tick = (now) => {
    const progress = Math.min(1, (now - start) / duration);
    const eased = 1 - Math.pow(1 - progress, 3);
    const value = Math.round(48 + 19 * eased);
    target.textContent = `${value}% · 48 → 61 → 67`;
    if (progress < 1) requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
}

function animatePillars() {
  const pills = [...document.querySelectorAll("[data-sequence]")];
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    pills.forEach((pill) => pill.classList.add("is-lit"));
    return;
  }
  pills.forEach((pill, index) => {
    window.setTimeout(() => pill.classList.add("is-lit"), 750 + index * 720);
  });
}

animateBalance();
animatePillars();
