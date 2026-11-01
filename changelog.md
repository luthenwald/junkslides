## Unreleased

## Highlighting with any theme

2026-11-01 · `rpoxkxtu::mmuqzvxr`

- Fixed: code is now highlighted in decks whose theme.css says nothing about code tokens, such as decks with a theme of your own. Your theme can still restyle every token.
- Improved: types in code are drawn in a softer shade rather than in italics.

## Highlighting with tree-sitter

2026-10-30 · `vvzpnppq::xnqlxrou`

- Improved: code blocks are now highlighted by your own `tree-sitter` command and grammars, which parse your code rather than matching patterns. Name the language after the opening fence, such as `haskell` or `hs`.
- Improved: without the command or a matching grammar, code is drawn plain, and `zeno serve` tells you once if the command is missing.

## Free placement, slide numbers and highlighting

2026-10-30 · `xnysvoyw::xokqnvtm`

- New: drag a cell anywhere, also partly off the slide and with the pointer in the margin around it.
- New: choose how drags and nudges snap, from 120 down to 10 pixels or not at all, in the status line or with `g` and `G` in canvas mode. Zeno remembers your choice for each deck.
- New: every slide shows its number, such as `01/26`, at the bottom right; your theme can move, restyle or hide it.
- New: code blocks are highlighted for their language, in shades of gray with the default theme.
- Improved: headings, paragraphs and list items keep the line breaks and indentation you wrote.
- Improved: placements are stored in pixels; layout files from earlier versions are read and converted when Zeno next saves.

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
