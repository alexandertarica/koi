const { applyCors, respond, validRespondentId } = require("../lib/http");
const { createRedis } = require("../lib/store");

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
]);

module.exports = async function handler(req, res) {
  if (!applyCors(req, res)) return respond(res, 403, { error: "Origin not allowed." });
  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return respond(res, 405, { error: "Use POST." });

  const body = req.body && typeof req.body === "object" ? req.body : {};
  if (!validRespondentId(body.respondentId) || !ALLOWED_EVENTS.has(body.event)) return respond(res, 400, { error: "Invalid demo event." });
  const timestamp = typeof body.timestamp === "string" && !Number.isNaN(Date.parse(body.timestamp)) ? body.timestamp : new Date().toISOString();

  try {
    const redis = createRedis();
    if (redis) await redis.rpush("koi-demo:events", JSON.stringify({ respondentId: body.respondentId, event: body.event, timestamp }));
  } catch {
    // Events are optional; logging must never interrupt the demo.
  }
  return res.status(204).end();
};
