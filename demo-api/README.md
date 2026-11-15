# Koi browser demo API

This is a separate Vercel project root for the browser demo's single `/api/demo-ai` function. Configure `OPENROUTER_API_KEY` in this Vercel project before using AI. The optional `OPENROUTER_MODEL` variable overrides the default model.

CORS accepts the GitHub Pages origin only. The function enforces per-device and global daily limits in warm function memory; Vercel may run multiple instances, so durable cross-instance quotas would require a shared store.
