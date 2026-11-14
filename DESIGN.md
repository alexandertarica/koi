# Koi — Design System

Koi lives on water. Every screen sits on the same blurred koi photograph; text
and lines are printed on it like ink; touchable things are glass floating on it.
Calm at rest, more on touch.

## 1. The water (background)

- `Brand/Images/KoiBackground` scaled to fill, blur 5.5, contrast 120%,
  saturation 112%, brightness −4.5%; drifts a few points with device tilt.
- Faint daylight tint over it by time of day (cool morning, clear midday, warm
  evening, deeper night), soft-light, very low opacity.
- Film grain overlay, soft-light, 10%.
- **Deep water wash: `#2B4067` at 33%** over everything. This is the base of
  the whole app.
- **Doing screens** (workout, run) add the same blue a step deeper: a vertical
  gradient 0 → 30% → 30% → 0.
- Status bar: the background repeats under it, fading out over 14pt.
- Content fades into the tab bar over its last 89pt.
- Legibility halo: one composited shadow under all content,
  `#0F1F3D` at 46%, radius 7.

## 2. Color

| Token | Value | Use |
|---|---|---|
| onBase (ivory) | `#F0E8DB` | primary text and lines on the water |
| onBaseMuted | ivory 92% | secondary text |
| deepWater | `#2B4067` | wash, training tint |
| glassInk | `#213352` | text on strong glass |
| caution | `#994D33` | over a limit, delete |
| divider | ivory 25–35% | hairlines |

No other accent colors. No pure white slabs, no solid fills behind content.

## 3. Type

- **Roboto Mono** Light and Regular for all text (`Brand/Fonts`).
- **KOI Numerals** for the biggest hero numbers where noted.
- SF for the giant workout numbers (80pt semibold) and stats (22–34pt semibold).
- Section labels: Regular 12pt, uppercase, tracking ~0.2em, muted.
- Titles 24pt Light. Body 15pt. Caption 12pt Regular. Nothing under 12pt.
- One hero number per screen (the dial score, 185 × 8, 2,200).

## 4. Spacing

Golden steps: **3, 5, 8, 13, 21, 34, 55, 89**.
- Screen margin 21. Between rows 21. Between major sections 34.
- Label → its content 13. Closely related 5–8.
- Header (wordmark, date, title) then 21 to the first content.

## 5. Layers

0. **Water**: the background above.
1. **Printed**: dials, hero numbers, labels, quiet rows, hairlines. Drawn
   straight on the water, no surface. Most of every "looking" screen.
2. **Fold-open**: tapping a quiet row reveals its controls in place, no box.
   One open per list.
3. **Glass**, one material at three strengths:
   - **Quiet**: 1pt ivory outline at 30%, no fill. Exits, secondary.
   - **Base**: ultra-thin material at 50% + ivory 35% outline. Chips, tiles,
     − / + circles, plate chips.
   - **Strong**: material 90% + white 26% fill, gradient outline (90% → 35%),
     soft white glow (radius 14). **The one main action on a screen.** Text in
     glassInk, uppercase, tracking 3.
4. **Chrome**: tab bar (Liquid Glass), header, smart-note handle.
5. **Overlays**: sheets, alerts, the tour (deep-blue dim with a cutout).

**Looking screens** (Hub, Intake, Movement, Progress, Profile): layers 0–2 plus
base-glass chips. No cards around lists.
**Doing screens** (workout, run, new to-do, new habit, journal): glass leads,
one strong button.

Rules: one strong button per screen; one open row per list; one hero number
per screen; never put glass under the dial or let a chip overlap an arc.

## 6. Components

- **KoiDial**: half-arc from the left edge; 72 ticks (every 5th longer, the one
  at the value longest), lit to the value; a line bright to the value and faint
  after, broken around a glass bead; inner bars per segment sized by weight,
  labels with value inside the curve; fades at both ends; draws itself in on
  appear; hold-and-slide to scrub.
- **Quiet row** (KoiFoldRow / nutrient row): label ⌄ · value right ·
  thin dotted bar; tap label to open.
- **GlassChip**: capsule, 32pt min height, 12pt Regular, optional SF icon 11pt
  light; `isOn` → stronger fill.
- **KoiTile**: icon, word, hint; 96pt min; 2–3 in a row.
- **KoiPrimaryButton**: strong glass capsule, 56–64pt tall.
- **KoiStat**: bold number, small-caps label, optional muted detail.
- **CheckCircle**: outline ring, fills ivory with a check.
- Tab bar: Hub (hexagon cluster), To-Do (checklist), Movement (walking
  figure), Intake (leaf); light glass, deep ink icons.

## 7. Motion and haptics

- `koiMorph`: the standard spring for content changes (dissolve + slight scale).
- Dials sweep in over 1.65s with a staged reveal.
- Haptics: tap (select), change (adjust), check (complete), land (start/commit),
  success (save/new best), tick (counting).
- New best: numbers glow, a pill pops, success haptic.
- To-do lands on the matrix with a ripple.

## 8. Voice

Calm, plain, short, a little warm. Sentence case. No exclamation marks except
celebrations. Say what happens, not how it works ("Koi moves it to urgent as
the date gets close."). Greeting: "Good morning, Sam." / "Still water, Sam."

## 9. Brand assets

`Brand/Images`: KoiBackground (the water), AppIcon (wordmark on deep water),
KoiWordmark, KoiRay, KoiLogo (+Big/Small), KoiFlame (streak), KoiLaunch,
widget backgrounds. Launch screen: KoiLaunch image on `#4C6688`.
