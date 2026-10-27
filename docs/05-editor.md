# 05/10 Editor

## Screen

```
+---------------------------+---+----------------------------------+
| cells pane                | | | slide pane                       |
|                           | | |                                  |
| 01/12 ------------------- | | |   +----------------------------+ |
| # Why lenses              | | |   |                            | |
|                           | | |   |  rendered slide, 16:9,     | |
| A lens is a pair of ...   | | |   |  scaled to fit             | |
|                           | | |   |                            | |
| notes  Mention Boomerang  | | |   +----------------------------+ |
|                           | | |                                  |
| 02/12 ------------------- | | |                                  |
+---------------------------+---+----------------------------------+
| status: mode, slide 01/12, overflow count, orphan count, notices  |
+-------------------------------------------------------------------+
```

- Left: the cells pane. Right: the slide pane. Between them a draggable
  divider.
- Either pane can be hidden; both cannot be hidden at once.
- Slides are numbered in the form `01/12` (current/total), in the cells pane
  dividers and in the status line.
- The slide pane shows the slide that contains the selected cell.

## Cells pane

- Each slide is a section that starts with a thin divider showing its number.
- Each cell is a plain source text area that grows with its content. No
  rendering on the left; the right pane renders.
- Notes cells are shown in a lighter gray with a small `notes` label.
- A cell with a problem (marker line, forbidden construct, overflow) shows a
  one-line quiet message under it. For overflow it reads "Does not fit its
  box on the slide."
- A slide without cells shows one quiet row, `empty slide`, which can be
  selected like a cell. `o`, `O` and `Enter` there insert its first cell.

## Modes

| Mode | Where | Purpose |
|---|---|---|
| Command | cells pane | Move between cells, restructure the deck |
| Edit | cells pane | Type inside one cell |
| Canvas | slide pane | Place, move, resize and style cells |

`Tab` switches focus between the cells pane (command mode) and the canvas.
Selection is shared: selecting a cell in either pane selects it in the other
and scrolls it into view.

Clicking into a cell's text enters edit mode for that cell; leaving the text
area commits, as `Esc` does. Keyboard focus follows the model: the selected
cell in command mode, the text area in edit mode, the slide pane when the
cells pane is hidden. Focusing also scrolls into view.

## Keymap

The keymap is modal, in the spirit of Helix and Jupyter's command and edit
modes. It is a starting point and should be easy to change in one place.

### Command mode

| Key | Action | Op |
|---|---|---|
| `j` / `k` | Select next / previous cell, across slides | |
| `}` / `{` | Select first cell of next / previous slide | |
| `J` / `K` | Move cell down / up, crossing into adjacent slides | `Move` |
| `o` / `O` | New content cell below / above, enter edit mode | `Insert` |
| `Enter` or `i` | Edit the selected cell | |
| `t` | Cycle kind (content, notes) | `CycleKind` |
| `d` | Cut | `Delete` plus clipboard |
| `y` | Copy | clipboard only |
| `p` / `P` | Paste below / above | `Paste` |
| `D` | Duplicate | `Duplicate` |
| `m` | Merge with next cell | `MergeWithNext` |
| `b` | Start a new slide at the selected cell | `InsertBreak` |
| `B` | Remove this slide's break (join with previous slide) | `RemoveBreak` |
| `u` / `U` | Undo / redo | |
| `Ctrl-[` / `Ctrl-]` | Hide or show cells pane / slide pane | |
| `Tab` | Focus the canvas | |

- The arrow keys up and down work as `k` and `j`.
- `b` on the first cell of a slide does nothing; that cell already starts
  one.
- The clipboard is the editor's own, not the system clipboard. It holds one
  cell with its ID, so a cut followed by a paste revives the cell and its
  layout (03-data-model.md, paste rule).
- New cells (`o`, `O`, `p`, `P`, `D`, a split) get their IDs on the server;
  the editor selects the new cell when the state that contains it arrives.
- `Tab` with the slide pane hidden says so instead.

### Edit mode

| Key | Action |
|---|---|
| `Esc` | Commit and return to command mode |
| `Alt-Enter` | Split the cell at the cursor (`Split`) |
| typing a line `---` | On commit, splits and starts a new slide (see 02-file-format.md) |

Text edits are sent as `EditText` while typing, debounced to about 200 ms, and
coalesce into one undo step per cell (see 03-data-model.md).

- The text area shows the text as typed; the deck gets it normalised
  (`normalize_edit`), so a new empty line being started is not trimmed away
  under the cursor.
- A `---` line is sent only on commit, so a half-typed break never moves
  text to a new slide.
- Entering edit mode puts the cursor at the end of the text.
- A marker line cannot be committed. `Esc` then keeps edit mode, focus
  stays, and the problem shows under the cell and in the status line. A
  second `Esc` drops the change.
- `Alt-Enter` on a draft with a `---` line asks for a commit first.
- If the cell being edited is removed outside Zeno, edit mode ends and the
  draft goes to the clipboard with the cell's ID, so `p` brings it back.

### Canvas mode

| Key | Action | Op |
|---|---|---|
| `j` / `k` | Select next / previous drawn cell on this slide | |
| `Enter` | Place the selected unplaced cell where it is drawn | `Place` |
| `h` `j` `k` `l` with `Alt`, or arrows | Nudge a placed cell by one grid unit | `Place` |
| `H` `J` `K` `L`, or `Shift` with arrows | Resize a placed cell by one grid unit | `Place` |
| `f` | Return the cell to the flow | `Unplace` |
| `v` | Cycle variant | `SetVariant` |
| `a` | Cycle alignment | `SetAlign` |
| `u` / `U` | Undo / redo | |
| `Tab` | Back to the cells pane | |

Mouse: click selects, drag moves (placing an unplaced cell), handles resize.

- `Esc` also returns to the cells pane. The status line shows `canvas`.
- Pressing a drawn cell selects it and enters canvas mode; an edit in
  progress is committed first. Clicking a cell in the cells pane returns to
  command mode.
- `j` and `k` move through the content cells of the slide in source order;
  from a notes cell or an empty slide, `j` selects the first one.
- Nudging or resizing an unplaced cell places it first, at the area where
  it is drawn, so `Enter` is not needed before an arrow key. `Enter` on a
  placed cell only says so.
- A nudge or resize that the grid's edge stops sends nothing, so it adds no
  undo step. A press without a move sends nothing either.
- The resize handle is the bottom-right corner of the selected placed cell
  in canvas mode; the hovered grid cell becomes the new corner.
- `v` cycles none, then the theme's variants in order; a variant the theme
  no longer lists goes back to none. `a` cycles none, start, center, end.
- While dragging, the cell is drawn at the snapped preview area; the
  preview stays until the next state, so the cell does not jump back while
  the `Place` travels. Leaving the slide pane ends the drag, as letting go
  does.

## Undo

Undo lives on the server (03-data-model.md, History), so it covers both panes
and external edits. `u` and `U` work in command and canvas modes.

## View state

Pane sizes and hidden panes are per-user view state, not deck data. The server
stores them outside the deck, in the user's config directory
(`~/.config/zeno/view.json`, keyed by deck path), and sends them on connect.
This keeps the deck folder clean and avoids browser storage APIs.

The divider's position is kept between 15 and 85 percent and saved when it is
let go; hiding or showing a pane is saved at once.

## Connection

The status line says `connecting` until the first state arrives, and
`offline, reconnecting` when the server goes away; the editor then tries again
every second and takes the state the server sends on connect. Ops are not
queued while offline: a key that would send one says so instead, and an edit
in progress stays in its cell until it can be committed.

## Visual style

- Grayscale values only, for the editor and for the default theme.
- Minimal: one sans and one mono typeface, hairline rules, generous spacing,
  no shadows, no colour, no icons where a word will do.
- Selection is a darker hairline outline (darker still in canvas mode);
  overflow is a dashed outline; problems are quiet gray text, never red.
- Outlines on the slide are the editor's only marks there. They never
  change the slide's layout, so what the canvas shows is what the theme
  draws.
- Motion only where it carries meaning (snapping during a drag).
