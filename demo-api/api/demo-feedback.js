const { applyCors, respond, validRespondentId } = require("../lib/http");
const { createRedis } = require("../lib/store");

const CHOICES = new Set(["Yes", "Maybe", "No"]);

function validTimestamp(value) {
  return typeof value === "string" && !Number.isNaN(Date.parse(value));
}

module.exports = async function handler(req, res) {
  if (!applyCors(req, res)) return respond(res, 403, { error: "Origin not allowed." });
  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return respond(res, 405, { error: "Use POST." });

  const body = req.body && typeof req.body === "object" ? req.body : {};
  const firstName = typeof body.firstName === "string" ? body.firstName.trim().replace(/\s+/g, " ").slice(0, 40) : "";
  const answers = body.answers && typeof body.answers === "object" ? body.answers : {};
  const email = typeof body.email === "string" ? body.email.trim().slice(0, 254) : "";
  const dailyUse = typeof answers.dailyUse === "string" ? answers.dailyUse.trim().slice(0, 240) : "";
  if (!validRespondentId(body.respondentId) || !firstName || !CHOICES.has(answers.wouldUse) || !CHOICES.has(answers.wouldPay) || !validTimestamp(body.startedAt) || !validTimestamp(body.finishedAt)) {
    return respond(res, 400, { error: "Add your name and choose an answer for both questions." });
  }
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return respond(res, 400, { error: "Check the email address or leave it blank." });

  try {
    const redis = createRedis();
    if (!redis) return respond(res, 503, { error: "Feedback storage is not connected yet." });
    const record = {
      respondentId: body.respondentId,
      firstName,
      answers: { wouldUse: answers.wouldUse, wouldPay: answers.wouldPay, dailyUse },
      email,
      startedAt: body.startedAt,
      finishedAt: body.finishedAt,
      submittedAt: new Date().toISOString(),
    };
    const stored = await redis.set(`koi-demo:feedback:${record.respondentId}`, JSON.stringify(record), { nx: true });
    if (stored !== "OK") {
      const existing = await redis.get(`koi-demo:feedback:${record.respondentId}`);
      if (!existing) return respond(res, 503, { error: "Feedback could not be saved. Please try again." });
      await redis.sadd("koi-demo:feedback-index", record.respondentId);
      return respond(res, 200, { ok: true });
    }
    await redis.sadd("koi-demo:feedback-index", record.respondentId);
    return respond(res, 200, { ok: true });
  } catch {
    return respond(res, 503, { error: "Feedback could not be saved. Please try again." });
  }
};
