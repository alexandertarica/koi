const test = require("node:test");
const assert = require("node:assert/strict");

const eventHandler = require("../api/demo-event");
const feedbackHandler = require("../api/demo-feedback");
const statsHandler = require("../api/demo-stats");
const store = require("../lib/store");
const { deleteKoiDemoKeys } = require("../lib/reset");

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
    assert.ok(store.createRedis());
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

  for (const event of ["tour_step_1", "tour_step_9", "tour_completed", "live_opened", "survey_submitted"]) {
    assert.equal((await invoke(eventHandler, { body: { respondentId, event, timestamp: now } })).statusCode, 204);
  }

  const invalid = await invoke(eventHandler, { body: { respondentId, event: "unknown" } });
  assert.equal(invalid.statusCode, 400);
  assert.equal((await invoke(eventHandler, { body: { respondentId, event: "tour_step_10" } })).statusCode, 400);

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

test("protected stats reset deletes only keys with the koi-demo prefix", async () => {
  const pages = new Map([
    ["0", ["7", ["koi-demo:feedback-index", "shared:account", "koi-demo:test:events"]]],
    ["7", ["0", ["koi-demo:events", "other-app:cache"]]],
  ]);
  const deleted = [];
  const fakeRedis = {
    async scan(cursor, options) {
      assert.equal(options.match, "koi-demo:*");
      return pages.get(String(cursor));
    },
    async del(...keys) {
      deleted.push(...keys);
      return keys.length;
    },
  };
  const count = await deleteKoiDemoKeys(fakeRedis);
  assert.equal(count, 3);
  assert.deepEqual(deleted, ["koi-demo:feedback-index", "koi-demo:test:events", "koi-demo:events"]);
  assert.ok(deleted.every((key) => key.startsWith("koi-demo:")));
});

test("stats reset requires the configured key and explicit confirmation", async () => {
  process.env.STATS_KEY = "local-test-key";
  const invalidKey = await invoke(statsHandler, { method: "GET", url: "/api/demo-stats?key=wrong&reset=confirm", query: { key: "wrong", reset: "confirm" } });
  assert.equal(invalidKey.statusCode, 404);

  delete process.env.UPSTASH_REDIS_REST_URL;
  delete process.env.UPSTASH_REDIS_REST_TOKEN;
  delete process.env.KV_REST_API_URL;
  delete process.env.KV_REST_API_TOKEN;
  const noStorage = await invoke(statsHandler, { method: "GET", url: "/api/demo-stats?key=local-test-key&reset=confirm", query: { key: "local-test-key", reset: "confirm" } });
  assert.equal(noStorage.statusCode, 503);
});

test("test feedback and events use an isolated namespace", async () => {
  const originalCreateRedis = store.createRedis;
  const writes = [];
  store.createRedis = () => ({
    async set(key, value) { writes.push(["set", key, JSON.parse(value)]); return "OK"; },
    async sadd(key, value) { writes.push(["sadd", key, value]); return 1; },
    async rpush(key, value) { writes.push(["rpush", key, JSON.parse(value)]); return 1; },
  });
  try {
    const event = await invoke(eventHandler, { body: { respondentId, event: "tour_step_1", timestamp: now, test: true } });
    const feedback = await invoke(feedbackHandler, { body: {
      respondentId,
      firstName: "Demo",
      answers: { wouldUse: "Yes", wouldPay: "Maybe" },
      email: "",
      startedAt: now,
      finishedAt: now,
      test: true,
    } });
    assert.equal(event.statusCode, 204);
    assert.equal(feedback.statusCode, 200);
    assert.ok(writes.some(([method, key]) => method === "rpush" && key === "koi-demo:test:events"));
    assert.ok(writes.some(([method, key]) => method === "set" && key === `koi-demo:test:feedback:${respondentId}`));
    assert.ok(writes.some(([method, key]) => method === "sadd" && key === "koi-demo:test:feedback-index"));
  } finally {
    store.createRedis = originalCreateRedis;
  }
});

test("stats excludes the earlier Demo test response and its events", async () => {
  const originalCreateRedis = store.createRedis;
  process.env.STATS_KEY = "local-test-key";
  store.createRedis = () => ({
    async smembers() { return [respondentId, "a94b16d7-8e5d-4a73-b145-99df8de382bf"]; },
    async mget() { return [
      JSON.stringify({ respondentId, firstName: "Demo", answers: { wouldUse: "Yes", wouldPay: "Yes" }, finishedAt: now }),
      JSON.stringify({ respondentId: "a94b16d7-8e5d-4a73-b145-99df8de382bf", firstName: "Maya", answers: { wouldUse: "Maybe", wouldPay: "No" }, finishedAt: now }),
    ]; },
    async lrange() { return [
      JSON.stringify({ respondentId, event: "visit", timestamp: now }),
      JSON.stringify({ respondentId: "a94b16d7-8e5d-4a73-b145-99df8de382bf", event: "visit", timestamp: now }),
    ]; },
  });
  try {
    const result = await invoke(statsHandler, { method: "GET", url: "/api/demo-stats?key=local-test-key", query: { key: "local-test-key" } });
    assert.equal(result.statusCode, 200);
    assert.match(result.responseText, /Total respondents<\/span><strong>1<\/strong>/);
    assert.match(result.responseText, /<td>visit<\/td><td>1<\/td>/);
    assert.doesNotMatch(result.responseText, /<td>Demo<\/td>/);
  } finally {
    store.createRedis = originalCreateRedis;
    delete process.env.STATS_KEY;
  }
});

test("keyed stats reset deletes only prefixed Redis keys", async () => {
  const originalCreateRedis = store.createRedis;
  const deleted = [];
  const pages = new Map([
    ["0", ["0", ["koi-demo:feedback-index", "shared:account", "koi-demo:events"]]],
  ]);
  process.env.STATS_KEY = "local-test-key";
  store.createRedis = () => ({
    async scan(cursor, options) { assert.equal(options.match, "koi-demo:*"); return pages.get(String(cursor)); },
    async del(...keys) { deleted.push(...keys); return keys.length; },
  });
  try {
    const result = await invoke(statsHandler, { method: "GET", url: "/api/demo-stats?key=local-test-key&reset=confirm", query: { key: "local-test-key", reset: "confirm" } });
    assert.equal(result.statusCode, 200);
    assert.match(result.responseText, /Removed 2 keys/);
    assert.deepEqual(deleted, ["koi-demo:feedback-index", "koi-demo:events"]);
  } finally {
    store.createRedis = originalCreateRedis;
    delete process.env.STATS_KEY;
  }
});
