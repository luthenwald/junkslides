# S2 measure

## Question

Can the client detect that a box overflows, and make text areas grow with
their content, without handwritten JS? Is CSS `field-sizing: content`
usable?

## What was tried

`spikes/s2_measure`, with Lustre 5.7.1. It is checked by
`spikes/browser/test/s2_test.gleam` in Chrome for Testing 156 over CDP. Run
with `just browser-test`.

Text areas, three ways:

1. `field-sizing: content` (CSS only).
2. A mirror: a grid wrapper whose `::after` shows `attr(data-value)` in the
   same grid cell as the text area. `data-value` comes from the model.
3. `rows` set from the line count of the model text.

Overflow, reported to the model:

- A hidden probe sits behind the visible box: same size, same content,
  `visibility: hidden`, a scroll container (`overflow: hidden` in one
  variant, `overflow: auto` with no scrollbar in the other), and
  `container-type: scroll-state`. Inside it, a tiny flag runs a 1 ms
  animation named `fits`, or `overflows` under
  `@container scroll-state(scrollable: bottom)`. Every change of state starts
  a new animation, and Lustre's `event.on("animationstart", ...)` decodes
  `animationName` into a message. The visible box itself stays
  `overflow: visible`, so nothing is clipped (P12).
- Rendered height in grid units, needed when an unplaced cell is dragged out
  of the flow: 18 probes of heights 1 to 18 units. The smallest one that
  reports `fits` is the cell's height. These would be rendered only for the
  dragged cell, at drag start.

## Results

Chrome 156:

| Check | Result |
|---|---|
| `field-sizing: content` | grows with lines (30 to 110 px) and with wrapping (to 330 px) |
| Mirror | grows with lines and with wrapping |
| `rows` from line count | grows with lines, not with wrapping (as expected) |
| Overflow probe, `overflow: hidden` | `fits` at 2 lines, `overflows` at 5, `fits` again at 2 |
| Overflow probe, `overflow: auto` | the same |
| Rows probe (30 px units, 30 px lines) | 2, then 5, then 2: exact |

Lessons:

- Lustre's `html.textarea(attrs, content)` sets the `value` property on
  every render, so a text area is always controlled: pass the model's text
  back in, or each render wipes what was typed.
- The animation events arrive a frame after the change, and probes report
  independently, so the model briefly sees mixed states. That is harmless
  for flags and counts.

Not covered:

- Safari. As far as I know, `scroll-state` container queries and
  `field-sizing` were Chromium-only or new elsewhere when this was written.
  If Safari lacks scroll-state queries, the probes never fire there.
  Fallbacks follow.

## What to use

- Text areas: the mirror (2). It is CSS only, works wherever grid and
  `attr()` in `content` work, and handles wrapping. `field-sizing: content`
  is simpler but newer. Using it alone would leave browsers without it
  with fixed-size text areas.
- Overflow: the scroll-state probe with `overflow: hidden`. It needs no JS,
  and the canvas, the cells pane mark and the status line count can all come
  from the model.
- Rendered size: the rows probe, only for the cell being dragged.

## Fallback options if Safari lacks scroll-state queries

1. Accept Chromium-only overflow flags for the prototype. Overflow is still
   visible on the canvas, since nothing is clipped, but it is not flagged.
2. Measure through an existing Gleam binding (for example `plinth`; not
   yet checked for which element measurements it exposes) in a Lustre
   `after_paint` effect. That is third-party JS FFI, so it is your call.
3. A minimal JS FFI of our own. Ruled out unless you decide otherwise.

## Consequences for the design

- None for the decisions. 04-layout.md's overflow rules (flagged, never
  clipped) and "rendered size rounded up to whole grid units" can be met
  without JS in Chromium.
- 05-editor.md (edit mode): text areas are controlled inputs fed from the
  model.

## Open decisions

- Which fallback to adopt if Safari support matters for the prototype.
  Decided 2026-10-27: the prototype targets Chromium (D18); option 1 for
  Safari until M5.
