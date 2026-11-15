const { applyCors, respond, validRespondentId } = require("../lib/http");
const store = require("../lib/store");

const ALLOWED_EVENTS = new Set([
  "visit",
  "guided_started",
  "meal_logged_text",
  "meal_logged_photo",
  "coach_shown",
  "coach_accepted",
  "pond_opened",
  "start_fresh",
  "feedback_submitted",
  "tour_completed",
  "live_opened",
  "survey_submitted",
]);

function allowedEvent(value) {
  return ALLOWED_EVENTS.has(value) || (typeof value === "string" && /^tour_step_[1-9]$/.test(value));
}

module.exports = async function handler(req, res) {
  if (!applyCors(req, res)) return respond(res, 403, { error: "Origin not allowed." });
  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return respond(res, 405, { error: "Use POST." });

  const body = req.body && typeof req.body === "object" ? req.body : {};
  if (!validRespondentId(body.respondentId) || !allowedEvent(body.event)) return respond(res, 400, { error: "Invalid demo event." });
  const timestamp = typeof body.timestamp === "string" && !Number.isNaN(Date.parse(body.timestamp)) ? body.timestamp : new Date().toISOString();

  try {
    const redis = store.createRedis();
    if (redis) {
      const namespace = body.test === true ? "koi-demo:test" : "koi-demo";
      await redis.rpush(`${namespace}:events`, JSON.stringify({ respondentId: body.respondentId, event: body.event, timestamp }));
    }
  } catch {
    // Events are optional; logging must never interrupt the demo.
  }
  return res.status(204).end();
};
