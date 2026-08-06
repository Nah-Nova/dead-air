# Dead Air brand

The canonical source for the identity. Edit this first, then push changes to the design
system project.

The colour tokens and type roles below are implemented in `Sources/DeadAir/Brand.swift`, and
the mark in `Sources/DeadAir/StatusIcon.swift`. If the code and this file ever disagree, this
file wins and the code is the bug.

## The idea

"Dead air" is the broadcast term for silence that was not supposed to happen. The app makes
that silence deliberate: mic off, keyboard frozen, camera watched. The identity comes from a
studio at the moment the signal drops, not from a padlock.

**Is.** Studio hardware. Tally lamps, VU scales, silkscreen legends, painted steel panels, a
needle at rest.

**Is not.** Security software. No padlocks, no shields, no crosshairs, no red alert glow. It
protects nothing, it silences things.

**Feels.** Precise and slightly deadpan. The tone of a piece of gear that does one job and has
a lamp to prove it.

## Palette

| Name | Hex | Role |
| --- | --- | --- |
| Studio dark | `#171C19` | Primary ground. Lights down, desk still on. |
| Panel sage | `#DDE0D8` | Light ground. Equipment paint, not paper cream. |
| Legend cream | `#E6E1D3` | Type on the dark ground. Slightly warm. |
| Tally amber | `#F5AE3A` | Lit lamp only. Glows and fills. |
| Oxide | `#CE7A53` | Accent voice, and the dead state. Tape, not danger. |
| Signal teal | `#63A38D` | Reserved. Live, passing, allowed. |

Three rules that are not negotiable:

1. **Amber is a lamp, never text.** It fills and glows. It never sets type. A rim around a
   whole panel is not a lamp either, that was tried and pulled.
2. **Oxide is the accent voice** and the colour of the dead state.
3. **Teal only ever means live.** Nothing else may be teal. Teal is also never a lamp bead: a
   lit tally is amber, so the app has one colour per fact rather than two.

### Derived values the implementation needs

The six above are the brand. These are arithmetic on them, recorded so nobody re-derives them
differently. They live in `Brand.swift`.

| Purpose | Light | Dark | Derivation |
| --- | --- | --- | --- |
| Oxide as type | `#994E2C` | `#CE7A53` | Oxide at 0.68 HSL lightness, the least darkening that clears 4.5:1 on Panel sage |
| Teal as type | `#3F6B5C` | `#63A38D` | Teal at 0.65 HSL lightness, same test |
| Lamp housing | `#171C19` | `#0B0E0C` | A step below Studio dark in dark, otherwise the bay and the plate are the same colour |
| Unlit bead | `#74756D` | `#74756D` | Housing relative, never the only channel, a state word always sits beside it |

Amber, cream and the two grounds keep their published hex in both themes. Anything else that
appears in the UI and is not in either table is a bug.

## Typography

Three roles, no fourth.

- **Display.** Heavy condensed sans, uppercase, tight tracking. Panel silkscreen. Wordmark and
  section heads only, never a sentence. Stack led by Avenir Next Condensed.
- **Body.** Neutral system sans. Never condensed, never uppercase.
- **Utility.** Monospace for anything a machine would print: states, timers, levels, hex.
  Tracked out when set in caps.

## The mark

One 64 unit grid, one 5 unit stroke, round caps. Only the interior line changes between
states, so the three read as one object doing different things.

| State | Drawing | Used for |
| --- | --- | --- |
| 01 Live | `polyline 4,32 14,32 19,15 24,49 29,32 60,32` | Mic is open |
| 02 Muted | `polyline 4,32 60,32` | Dead air |
| 03 Locked | Keycap rounded rect `x8 y14 w48 h36 r7` with `polyline 19,32 45,32` inside | Cleaning mode |

The flat line is the whole idea of the name, and it survives being 16 points tall. Design the
state family first and the app icon second, because the small one is the one people see.

**Shipped.** `StatusIcon.swift` draws all three as vectors, so they stay sharp at any size
and need no `@2x` pair. The designed PNG templates are kept in `Resources/MenuBar` as the
design source.

Two things the implementation had to settle that the drawing above does not say:

- **Stroke is 6 units, not 5.** At an 18 pt render 5 units lands on 1.4 pt, under the 1.5 px
  floor a 1x menu bar needs. 6 gives 1.69 pt.
- **The polylines run 5 to 59, not 4 to 60.** Round caps put ink 3 units past each endpoint,
  so starting at 4 left one unit of margin where the two units below are required.

### Alternates already explored, do not re-propose as the lead

- **Tally sign**, a lamp housing with a dot and a bar. Best story of the set, hopeless at 16
  points. App icon only.
- **Muted capsule**, a circle with a bar. Clean, but it is already every mute button on earth.
- **Carrier gap**, an interrupted broadcast arc. Everyone reads it as a wifi problem.

## macOS constraints

| Asset | Size | Rules |
| --- | --- | --- |
| Menu bar icon | 16 and 18 pt, 1x and 2x | Monochrome black with alpha, marked as a template so macOS tints it. Stroke no thinner than 1.5 px at 1x. Two units of padding inside the grid. |
| App icon | 1024 x 1024 | Squircle on the current macOS grid. The mark sits inside a lit tally housing. The only place detail is allowed. |
| State set | 3 variants | Same grid, same stroke, same optical centre, so the swap does not shift in the bar. |

## Do

- Test every mark at 16 points before falling in love with it at 400.
- Let the amber lamp be the only bright thing in the frame.
- Keep the stroke weight identical across all three states.
- Optically centre the flat line, which sits slightly high when centred by maths.

## Do not

- Add a padlock, shield, or crosshair. Wrong genre entirely.
- Use a gradient or a glow in the menu bar asset. Template icons discard it.
- Draw a literal microphone. Three features, only one of them is a mic.
- Signal camera blocking. **The app watches the camera, it cannot switch it off.** macOS
  exposes no API for disabling a camera, so any design implying it does is a lie about the
  product.
