# S1 drag

## Question

Can Lustre handle pointer down, move and up, with pointer capture, to drag
and resize a box snapping to a 32x18 grid, smoothly and without handwritten
JS?

## What was tried

`spikes/s1_drag`, with Lustre 5.7.1 and lustre_dev_tools 2.4.0 (which
downloads Bun 1.2.22 to bundle). It is checked by `spikes/browser/test/s1_test.gleam` in
Chrome for Testing 156 (headless shell), driven over the DevTools protocol
from Gleam. Run with `just browser-test`.

- Fit: the 1920x1080 slide is centred with `left: 50%; top: 50%;
  translate: -50% -50%` inside a `container-type: size` stage, and scaled
  with `scale: min(100cqw / 1920px, 100cqh / 1080px)`. That is CSS typed
  arithmetic: dividing a length by a length gives a number.
- Approach A, pure Lustre and CSS. The box takes `pointerdown`. The event's
  `offsetX` and `offsetY`, divided by 60, give the grab cell inside the box.
  An overlay of 32x18 transparent hit cells sits above the slide during a
  drag; each cell reports `pointerenter` with its own column and row. A move
  is start plus the cell delta from the grab cell, and a resize uses the
  hovered cell as the bottom-right corner. Both are clamped to the grid. One
  commit happens on `pointerup` or `pointercancel`, caught on the
  full-viewport stage.
- Approach B (plinth for `setPointerCapture` and `getBoundingClientRect`)
  was not needed.

## Results

Chrome 156, viewport 1280x800:

| Check | Result |
|---|---|
| Fit | the slide is 1280x720 at (0, 40): correct scale and centring |
| Move by (+10, +6) along a 10-step path | exact |
| Drag past the right and bottom edges | clamped exactly |
| Resize larger, past the top-left corner (minimum 1x1), and back | exact |
| Release below the slide, inside the window | ends the drag and commits once |
| One commit per drag | yes (5 drags, 5 commits) |
| Cost per move | about 13 ms including the CDP round trip; no visible work beyond one box restyle per cell crossed |

Things learned on the way:

- `offsetX` and `offsetY` are in the target's own unscaled coordinates, so
  the grab cell is right at any scale. Children of the box need
  `pointer-events: none` so that the box is always the event target (the
  resize handle is the exception).
- Taking the grab cell from the first `pointerenter` instead is off by the
  first movement. The overlay appears one animation frame after the press,
  because Lustre renders on the next frame.
- The overlay can be rendered once and shown with a class, or created per
  drag (with or without `element.memo`). Both work. Rendering it once avoids
  creating 576 nodes at every press.
- Synthetic input sent over CDP has to be paced by about one frame (20 ms).
  Unpaced events reached the page out of step with the frames, which first
  looked like app bugs. Real pointers never move that fast.

Not covered:

- Safari. No automated Safari check was set up. The features used are
  pointer events, `offsetX`, container query units, the individual
  `translate` and `scale` properties, and typed arithmetic. The last one
  is the newest. If Safari lacks it, the fallback is to size the slide grid
  in container units (`width: min(100cqw, 100cqh * 16 / 9)` with `fr`
  tracks and type in `cqw`) instead of scaling a 1920 px design space.
- A release outside the browser window. Without pointer capture the page
  may not see that `pointerup`. The drag then stays active until the next
  `pointerup`, `pointercancel` or `pointerleave` on the stage; handling
  `pointerleave` as a cancel would close the gap.

## What to use

Approach A. No JS and no bindings are needed for drag, resize, snapping or
clamping. The single `Place` op is sent on `pointerup`, as 04-layout.md
specifies.

## Consequences for the design

- None for the decisions. 04-layout.md ("one `Place` op is sent on pointer
  up") and the 1920x1080 design space work as written.
- Placing an unplaced cell needs its rendered size; see S2 (rows probe).

## Open decisions

- Whether a Safari check is wanted before M4, by hand or through
  safaridriver. Decided 2026-10-27: no, the prototype targets Chromium
  (D18).
