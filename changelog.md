## Unreleased

## New default fonts

2026-11-01 · `wutumzxl::ztxqruvq`

- New: slides are set in et-book, with code in Victor Mono, and both come with Zeno, so a deck looks the same on any machine. Your theme can choose other fonts. A theme that already names a font keeps it for text; to use et-book, remove the font name from your `theme.css`.
- New: exports include the fonts in a `fonts/` folder.
- New: `just run` starts Zeno from the last build, without compiling first.
- Improved: the source text in the editor is in Victor Mono too.

## Export to HTML

2026-11-01 · `zxkrplnw::kquwnpqr`

- New: press `E` or run `zeno export` to write your deck as a folder you can open, host or zip, with your theme and images.
- New: the exported page steps between slides with the arrow keys, space and Page Down, fits each slide to the window, and links to a slide with `#3`. It runs no scripts.
- New: printing the page gives one slide per page, so you can save a PDF.

## Tables

2026-11-01 · `squnwrkv::nnuntwst`

- New: write tables as rows of pipes with a line of dashes under the header. Colons in the dashes align a column.
- New: tables have a quiet look in every theme: a semibold header over one firm rule and faint lines between rows, in shades of the text colour. They scale with a cell's variant, and your theme can restyle them.
- New: a table is as wide as its content and wraps at the edge of its cell. A table too wide for its box is flagged like any other overflow, and a row that does not fit the header is noted under the cell.

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
