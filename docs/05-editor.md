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
  one-line quiet message under it.

## Modes

| Mode | Where | Purpose |
|---|---|---|
| Command | cells pane | Move between cells, restructure the deck |
| Edit | cells pane | Type inside one cell |
| Canvas | slide pane | Place, move, resize and style cells |

`Tab` switches focus between the cells pane (command mode) and the canvas.
Selection is shared: selecting a cell in either pane selects it in the other
and scrolls it into view.

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

### Edit mode

| Key | Action |
|---|---|
| `Esc` | Commit and return to command mode |
| `Alt-Enter` | Split the cell at the cursor (`Split`) |
| typing a line `---` | On commit, splits and starts a new slide (see 02-file-format.md) |

Text edits are sent as `EditText` while typing, debounced to about 200 ms, and
coalesce into one undo step per cell (see 03-data-model.md).

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

## Undo

Undo lives on the server (03-data-model.md, History), so it covers both panes
and external edits. `u` and `U` work in command and canvas modes.

## View state

Pane sizes and hidden panes are per-user view state, not deck data. The server
stores them outside the deck, in the user's config directory
(`~/.config/zeno/view.json`, keyed by deck path), and sends them on connect.
This keeps the deck folder clean and avoids browser storage APIs.

## Visual style

- Grayscale values only, for the editor and for the default theme.
- Minimal: one sans and one mono typeface, hairline rules, generous spacing,
  no shadows, no colour, no icons where a word will do.
- Selection is a darker hairline outline; overflow is a dashed outline;
  problems are quiet gray text, never red.
- Motion only where it carries meaning (snapping during a drag).
