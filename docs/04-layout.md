# 04/10 Layout

## The slide

- Fixed 16:9 aspect ratio.
- Design space of 1920x1080 px, scaled to fit the right pane with a CSS
  transform. Nothing is ever stored in screen pixels.
- A grid of 32 columns by 18 rows. One grid unit is 60x60 px in the design
  space, so grid units are square.

## Two ways a cell sits on a slide

Every content cell is either unplaced or placed. There is no per-slide mode.

Unplaced cells flow in the body area. The theme defines the body area as a
grid area (for example columns 2 to 30, rows 2 to 16). Inside it, unplaced
cells stack vertically in source order with the theme's gap. This is where
every new cell appears, so new content is always visible without any
placement decision.

Placed cells have an explicit grid area (`col`, `row`, `w`, `h`, in grid
units) and are drawn there, above the body flow. Placing a cell takes it out
of the flow; unplacing it returns it to the flow at its source-order position.

If placed cells cover the body area, flowing cells are still drawn there and
may overlap; overlaps are visible, not prevented. Among placed cells, later
cells in source order are drawn on top.

Notes cells are never drawn on the slide. Their layout records are kept but
inactive.

## Placing and moving

- Dragging an unplaced cell out of the flow places it at the drop location,
  with its current rendered size rounded up to whole grid units. The size
  and position come from the drawn element itself: a pointer or key event
  carries its target, whose layout offsets (`offsetLeft`, `offsetWidth` and
  so on, summed up to the slide) are in design pixels whatever the scale.
- Dragging a placed cell moves it; dragging a handle resizes it. Both snap to
  grid units and are clamped to the grid.
- While dragging, the client keeps a transient preview; one `Place` op is sent
  on pointer up, so a drag is one undo step.
- Keyboard equivalents are in 05-editor.md.

Moving a cell to another slide keeps its placement (layout follows identity).
If it overlaps something there, that is visible and the user adjusts it.

## Style

A cell record may carry:

- `variant`: one name from the theme's variant list.
- `align`: `start`, `center` or `end`.

No free-form CSS per cell in the prototype. The theme stays in charge of the
look, so a grayscale theme stays grayscale.

Default variant list for the prototype theme: `large`, `small`, `quiet`,
`emphasis`. Cycling variants moves through none, then each name in order.

## Overflow

A cell overflows when its rendered content does not fit its box: a placed
cell's grid area, or for unplaced cells, the body area as a whole.

- Overflow is flagged, never fixed silently: the cell gets a dashed outline on
  the canvas, the matching cell in the left pane gets a quiet mark, and the
  status line shows a count.
- For unplaced cells, the flagged ones are those that do not fit: a cell
  overflows when the flow up to and including it does not fit the body. The
  cells before it stay unmarked.
- Overflow at the bottom and at the right both count.
- Nothing is clipped. Shrink-to-fit is planned for later.
- Detection is CSS only (spike S2): behind every drawn box a hidden copy is
  a scroll-state container, and its flag starts one of two animations,
  which the editor hears. The copies cover every slide, so the count and
  the marks cover the whole deck, also with the slide pane hidden.

## Orphans

When a cell or slide is retired (deleted, merged away, cut), its layout record
moves to `orphans` in layout.json with a timestamp, instead of being deleted.

Why keep them: undo does not need them (it uses snapshots), but external edits
do. If a cell is cut in an outside editor, the file is saved, and the cell is
pasted back later, its marker reappears and the record is revived.

Orphans are removed only by the `PurgeOrphans` command in the prototype. The
status line shows the number of orphans.

## Theme contract

theme.css is plain CSS written by the user. The renderer produces this
structure, and the theme styles it:

| Element | Contract |
|---|---|
| `.zeno-slide` | The 1920x1080 slide, a CSS grid of 32x18 units of 60px |
| `.zeno-body` | The body area; the theme sets its `grid-area` and the flow `gap` |
| `.zeno-cell` | Every drawn cell |
| `.zeno-cell[data-placed]` | A placed cell; its `grid-area` is set inline by Zeno |
| `.zeno-cell[data-variant="large"]` | Variant styling, one selector per variant |
| `.zeno-cell[data-align="center"]` | Alignment styling |

The editor's stylesheet gives this structure its base: the slide's size and
grid, a body area (columns 2 to 30, rows 2 to 16) that stacks cells as a
flex column, no outer margins inside a cell, images no wider than their
cell, links in the text colour, and `text-align` for `data-align`. These
rules have zero specificity (`:where`), so any rule in theme.css wins.

Theme tokens are CSS custom properties on `:root` (colours, type scale,
spacing). The default theme uses grayscale values only, in a quiet, minimal
style. The theme also lists its variants in a custom property. The server reads this
line from theme.css (no browser measurement needed) and sends the list to the
editor:

```css
:root { --zeno-variants: "large small quiet emphasis"; }
```

When theme.css changes on disk, the server tells clients to reload the
stylesheet; layout records are unaffected. The editor links the theme as
`/theme.css?v=N` and changes `N`, so the browser fetches it again.
