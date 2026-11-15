# Koi

One honest score for your day. Koi turns habits, nutrition and exercise into a
single daily Balance, on a calm, watery iPhone app.

Try the [browser demo](https://alexandertarica.github.io/koi/). It includes
interactive onboarding, daily tracking, meal estimates, and workout plan import.
Apple Health, Calendar, and on-device Apple Intelligence require the iPhone app.

- `SPEC.md`: what Koi does
- `DESIGN.md`: how it looks
- `AGENTS.md`: how the code is organized and built
- `HANDOFF.md`: build status

## Setup

1. Copy `Secrets.example.plist` to `Koi/Config/Secrets.plist` and fill in the token.
2. Open `Koi.xcodeproj` in Xcode 26, select your team, run on an iPhone 17 Pro simulator.

## Built at the CPVC AI Hackathon (Nov 13–15, 2026)

All code in this repository was written during the hackathon, starting Friday
evening. The idea was brought in beforehand.

## Credits

- **OpenAI Codex**: wrote the app code from the spec and design docs, working
  through the phases in `HANDOFF.md`.
- **Claude (Anthropic)**: planning, design review, side-by-side screen checks,
  and the TestFlight release.
- **In-app AI**: meal photos and text become calorie and nutrient estimates, and
  workout screenshots become sets and reps. This runs through Koi's own API
  proxy (OpenRouter), so no keys ship in the app.
- **Roboto Mono** (Google Fonts, Apache 2.0).
