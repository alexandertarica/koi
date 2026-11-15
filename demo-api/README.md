# Koi browser demo API

This is a separate Vercel project root for the browser demo's `/api/demo-ai`, `/api/demo-feedback`, `/api/demo-event`, and `/api/demo-stats` functions. Configure `OPENROUTER_API_KEY` in this Vercel project before using AI. The optional `OPENROUTER_MODEL` variable overrides the default model.

The `coach` task accepts `{ task: "coach", context, deviceId }` and returns `{ message, action }`. The context is compact JSON containing the recent event, daily pillar scores, nutrition goals and totals, optional pond rank, and the next calendar event when available. Actions are limited to `adjustGoal`, `addTodo`, or `none`; no provider key is sent by the app.

CORS accepts the GitHub Pages origin only for browser POST requests. The AI function enforces per-device and global daily limits in warm function memory; Vercel may run multiple instances, so durable cross-instance quotas would require a shared store.

Judge feedback and events use Upstash Redis through `@upstash/redis`. Set
`UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` in this project. Feedback
is stored under a random respondent ID with the first name, two answers, optional
daily-use note and optional email. Events contain only the respondent ID, event
type and timestamp. Without Redis configuration, event writes return an empty
success and are dropped; feedback returns a friendly service-unavailable error.

Set `STATS_KEY` to a private value to enable `/api/demo-stats?key=...`. The page
shows aggregate answers, respondent comments, separately listed opt-in emails,
event totals and a CSV download. The stats route returns not found unless the
provided key matches `STATS_KEY`. Add `&reset=confirm` to the keyed stats URL to
delete every Redis key beginning with `koi-demo:`. The reset scans the prefix and
deletes matching keys in batches, leaving keys for any other app untouched.
Requests carrying `test: true` are stored under `koi-demo:test:*` and stay out of
the normal respondent totals and event stream.
