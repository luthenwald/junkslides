## Unreleased

## Smoother editing

2026-10-27 · `zzolprty::lzrnuotz`

- New: `X` in command mode removes the layout kept for deleted cells, as one step you can undo.
- Improved: typing stays quick in decks with a hundred slides or more.
- Improved: when you change theme.css, the slide keeps its old look until the new one has loaded, without a flash of unstyled text.
- Improved: a cell you let go of after a drag stays where you dropped it while the change is saved, instead of jumping back for a moment.
- Fixed: a file or folder in your deck named like one of the editor's own paths is served again.
- Fixed: when the port is already in use, `zeno serve` says so in one line instead of printing an error report.

## The editor

2026-10-27 · `noqxvxto::mzyotymp`

- New: `zeno init` creates a deck folder with a default theme, and `zeno serve` opens it in the browser editor.
- New: the cells pane, where you write each cell and move through the deck with modal keys.
- New: the slide pane, where you drag cells into place, resize them, nudge them with the keyboard and pick a style variant and alignment.
- New: cells that do not fit their box are outlined and counted in the status line.
- New: edits you make to deck.md or theme.css in another editor show up at once, and the layout of each cell is kept.
- New: undo and redo cover every change, also changes made outside Zeno.
