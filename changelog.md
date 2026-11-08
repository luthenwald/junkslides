## Unreleased

- New: an example deck in `examples/showcase`, a short talk about junkslides with a theme of its own that uses every feature.
- Improved: Zeno is now called junkslides. The command, the settings file and the names your theme uses changed with it: rename `zeno.toml` to `junkslides.toml`, and in `theme.css` write `js-` where it said `zeno-`, such as `.js-cell` and `var(--js-accent)`.

## Marks, charts and embedded figures

2026-11-03 · `vtqumtsx::qyqytuws`

- New: mark words for your theme with a span and a class, such as `[2,040]{.now}`. Your theme lists the classes it knows in `--js-marks` and decides how they look; a cell that uses another class gets a note.
- New: a line of attributes above a code block lights some of its lines (`lit="2 5-7"`) and marks words inside it between two characters you choose, such as `now="⟦⟧"`.
- New: code in a language without a tree-sitter grammar is shaded by simple rules, with comments, keywords, capitalised names, numbers and operators. The `[code]` settings choose the keywords and comment markers, and can send a language to these rules even when it has a grammar.
- New: an `.svg` image alone in its paragraph is drawn into the slide, so your theme's rules and fonts reach the drawing. One with scripts or links to other files stays a plain image, and junkslides tells you why.
- New: a `.json` image is a chart that junkslides draws at the size of its cell: lines, dots, stacked bars or bars, with log scales, a legend, several panels, and a switch between measures that works in the exported page without scripts.
- New: an `.html` image is a page of your own in a frame, with its script running, such as an animation. It is kept apart from the editor and from your deck's files. In the editor a press on it selects the cell.
- New: slide numbers can also show as `01 / 12`.
- Improved: the editor's live connection only accepts the editor's own page, so another site open in your browser cannot reach your deck.

## Deck settings

2026-11-02 · `krmyskqr::tosxonru`

- New: a `junkslides.toml` in your deck's folder sets its fonts, colours, text size, line height, code size, slide numbers and margins, without writing CSS. junkslides applies a change as soon as you save the file.
- New: a font is a family name plus the files for its regular, italic and bold faces, anywhere in the deck's folder. Exports and PDFs include those files, with licence files next to them.
- New: slide numbers can show as `01/12`, as `01`, or not at all.
- New: your `theme.css` can use the settings as CSS variables, such as `var(--js-accent)`, and any rule in it still wins over them.
- Improved: a new deck gets a `junkslides.toml` with et-book, Victor Mono and the grey palette, and its `theme.css` is down to the style variants. Decks you already have look the same. Slide numbers in a new deck use the quiet grey (#777), a little darker than before.
- Improved: if `junkslides.toml` has a mistake, junkslides says which key is wrong and keeps the settings it had. An export waits until the file is fixed.

## Fonts from your theme

2026-11-02 · `lxrrkoxp::vnttkvwl`

- New: your `theme.css` decides the fonts. A new deck gets et-book for text and Victor Mono for code in its `fonts/` folder, and the default theme loads them. In a deck made earlier, a theme that names no font now shows the browser's fonts; to keep et-book and Victor Mono, copy `fonts/` and the `@font-face` lines from a new deck's theme.
- New: exports and PDFs include the fonts and other files your theme loads with `url()`, wherever they sit in the deck's folder, together with licence files next to them. Fonts your theme doesn't use stay out.
- Improved: junkslides tells you when a file your theme loads is missing, lies outside the deck, or uses a path starting with `/`.

## Delete slides

2026-11-02 · `vvvxkwto::ktsyysmp`

- New: `d` on an empty slide deletes it.
- New: `Ctrl-Shift-D` deletes the selected slide with all its cells. It is the Control key on a Mac too, and `u` brings the slide back.

## Run with gleam

2026-11-02 · `zywpnxsv::trquxrql`

- New: `gleam run serve <folder>`, `gleam run init <folder>` and `gleam run export <folder>` work from the project folder, with no `just` needed. Serving builds the editor first, so the page always matches the source.

## Export to PDF

2026-11-01 · `rmklpwsu::pvwrmorp`

- New: press `F` or run `junkslides export --pdf` to get a PDF of your deck, one slide per page, next to the exported page and named after your deck's folder.
- New: junkslides prints with Chrome, Chromium, Edge or Brave, whichever it finds first. Set `JUNKSLIDES_CHROME` to choose a program.
- Improved: if printing fails, junkslides says why and your last PDF stays as it was.

## New default fonts

2026-11-01 · `wutumzxl::ztxqruvq`

- New: slides are set in et-book, with code in Victor Mono, and both come with junkslides, so a deck looks the same on any machine. Your theme can choose other fonts. A theme that already names a font keeps it for text; to use et-book, remove the font name from your `theme.css`.
- New: exports include the fonts in a `fonts/` folder.
- New: `just run` starts junkslides from the last build, without compiling first.
- Improved: the source text in the editor is in Victor Mono too.

## Export to HTML

2026-11-01 · `zxkrplnw::kquwnpqr`

- New: press `E` or run `junkslides export` to write your deck as a folder you can open, host or zip, with your theme and images.
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
- Improved: without the command or a matching grammar, code is drawn plain, and `junkslides serve` tells you once if the command is missing.

## Free placement, slide numbers and highlighting

2026-10-30 · `xnysvoyw::xokqnvtm`

- New: drag a cell anywhere, also partly off the slide and with the pointer in the margin around it.
- New: choose how drags and nudges snap, from 120 down to 10 pixels or not at all, in the status line or with `g` and `G` in canvas mode. junkslides remembers your choice for each deck.
- New: every slide shows its number, such as `01/26`, at the bottom right; your theme can move, restyle or hide it.
- New: code blocks are highlighted for their language, in shades of gray with the default theme.
- Improved: headings, paragraphs and list items keep the line breaks and indentation you wrote.
- Improved: placements are stored in pixels; layout files from earlier versions are read and converted when junkslides next saves.

## Smoother editing

2026-10-27 · `zzolprty::lzrnuotz`

- New: `X` in command mode removes the layout kept for deleted cells, as one step you can undo.
- Improved: typing stays quick in decks with a hundred slides or more.
- Improved: when you change theme.css, the slide keeps its old look until the new one has loaded, without a flash of unstyled text.
- Improved: a cell you let go of after a drag stays where you dropped it while the change is saved, instead of jumping back for a moment.
- Fixed: a file or folder in your deck named like one of the editor's own paths is served again.
- Fixed: when the port is already in use, `junkslides serve` says so in one line instead of printing an error report.

## The editor

2026-10-27 · `noqxvxto::mzyotymp`

- New: `junkslides init` creates a deck folder with a default theme, and `junkslides serve` opens it in the browser editor.
- New: the cells pane, where you write each cell and move through the deck with modal keys.
- New: the slide pane, where you drag cells into place, resize them, nudge them with the keyboard and pick a style variant and alignment.
- New: cells that do not fit their box are outlined and counted in the status line.
- New: edits you make to deck.md or theme.css in another editor show up at once, and the layout of each cell is kept.
- New: undo and redo cover every change, also changes made outside junkslides.
