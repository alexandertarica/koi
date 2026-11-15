const test = require("node:test");
const assert = require("node:assert/strict");

const eventHandler = require("../api/demo-event");
const feedbackHandler = require("../api/demo-feedback");
const statsHandler = require("../api/demo-stats");
const { createRedis } = require("../lib/store");

function invoke(handler, { method = "POST", body = {}, url = "/", origin = "https://alexandertarica.github.io", query = {} } = {}) {
  const headers = {};
  const req = { method, body, url, query, headers: { origin } };
  let statusCode = 200;
  let responseBody;
  let responseText = "";
  const res = {
    get statusCode() { return statusCode; },
    set statusCode(code) { statusCode = code; },
    status(code) { statusCode = code; return this; },
    json(value) { responseBody = value; return this; },
    setHeader(name, value) { headers[name] = value; },
    end(value = "") { responseText = value; return this; },
  };
  return Promise.resolve(handler(req, res)).then(() => ({ statusCode, responseBody, responseText, headers }));
}

const respondentId = "8d0a1fd5-2c11-4f07-84c4-98c09fcf8302";
const now = "2026-11-14T19:00:00.000Z";

test("Redis accepts the Vercel KV environment variable aliases", () => {
  const oldValues = Object.fromEntries(["UPSTASH_REDIS_REST_URL", "UPSTASH_REDIS_REST_TOKEN", "KV_REST_API_URL", "KV_REST_API_TOKEN"].map((key) => [key, process.env[key]]));
  delete process.env.UPSTASH_REDIS_REST_URL;
  delete process.env.UPSTASH_REDIS_REST_TOKEN;
  process.env.KV_REST_API_URL = "https://redis.example.test";
  process.env.KV_REST_API_TOKEN = "test-token";
  try {
    assert.ok(createRedis());
  } finally {
    for (const [key, value] of Object.entries(oldValues)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test("event endpoint validates events, restricts browser origins, and fails silently without storage", async () => {
  delete process.env.UPSTASH_REDIS_REST_URL;
  delete process.env.UPSTASH_REDIS_REST_TOKEN;
  const valid = await invoke(eventHandler, { body: { respondentId, event: "visit", timestamp: now } });
  assert.equal(valid.statusCode, 204);
  assert.equal(valid.headers["Access-Control-Allow-Origin"], "https://alexandertarica.github.io");

  const invalid = await invoke(eventHandler, { body: { respondentId, event: "unknown" } });
  assert.equal(invalid.statusCode, 400);

  const blocked = await invoke(eventHandler, { body: { respondentId, event: "visit" }, origin: "https://example.com" });
  assert.equal(blocked.statusCode, 403);
});

test("feedback requires a name and two choices, then reports missing storage clearly", async () => {
  delete process.env.UPSTASH_REDIS_REST_URL;
  delete process.env.UPSTASH_REDIS_REST_TOKEN;
  const invalid = await invoke(feedbackHandler, { body: { respondentId, startedAt: now, finishedAt: now } });
  assert.equal(invalid.statusCode, 400);

  const body = {
    respondentId,
    firstName: "Maya",
    answers: { wouldUse: "Yes", wouldPay: "Maybe", dailyUse: "A calmer plan" },
    email: "",
    startedAt: now,
    finishedAt: now,
  };
  const unavailable = await invoke(feedbackHandler, { body });
  assert.equal(unavailable.statusCode, 503);
  assert.equal(unavailable.responseBody.error, "Feedback storage is not connected yet.");

  const blocked = await invoke(feedbackHandler, { body, origin: "https://example.com" });
  assert.equal(blocked.statusCode, 403);
});

test("stats page stays private unless the configured key matches", async () => {
  process.env.STATS_KEY = "local-test-key";
  const hidden = await invoke(statsHandler, { method: "GET", url: "/api/demo-stats?key=wrong", query: { key: "wrong" } });
  assert.equal(hidden.statusCode, 404);

  delete process.env.STATS_KEY;
  const unset = await invoke(statsHandler, { method: "GET", url: "/api/demo-stats?key=anything", query: { key: "anything" } });
  assert.equal(unset.statusCode, 404);
});
