# Koi browser demo API

This is a separate Vercel project root for the browser demo's single `/api/demo-ai` function. Configure `OPENROUTER_API_KEY` in this Vercel project before using AI. The optional `OPENROUTER_MODEL` variable overrides the default model.

The `coach` task accepts `{ task: "coach", context, deviceId }` and returns `{ message, action }`. The context is compact JSON containing the recent event, daily pillar scores, nutrition goals and totals, optional pond rank, and the next calendar event when available. Actions are limited to `adjustGoal`, `addTodo`, or `none`; no provider key is sent by the app.

CORS accepts the GitHub Pages origin only. The function enforces per-device and global daily limits in warm function memory; Vercel may run multiple instances, so durable cross-instance quotas would require a shared store.
