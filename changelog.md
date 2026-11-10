## Unreleased

## An installed command and an editor to try online

0.2.0 · 2026-11-10 · `oplnwwpp::umlmtuvk`

- New: the editor can be tried in a browser with nothing installed. `docs/` holds a copy that runs on the showcase deck from plain files, as GitHub Pages serves them: edit, place and undo as usual, and press `E` to save `deck.md` and `layout.json`. Your browser keeps your edits there across reloads until you choose "start over". The exported slides moved to `docs/slides/`.
- New: on that site, "open a folder" works on a copy of a deck from your computer, with its settings, theme, drawings and charts. Nothing is written to the folder or sent anywhere, and the copy stays in your browser until you close it. It needs a browser built on Chromium, and pictures and font files are not copied.
- New: a slide can go without its number or without the marks your theme draws on every slide, such as a progress dot. Press `n` or `.` on the slide in the editor, and again to bring them back. Themes see `data-marks="off"` on such a slide.
- Improved: a new deck is set in fonts your system already has, Charter for text and Menlo for code with common fallbacks, so `junkslides init` no longer copies font files into it. Decks you already have keep their fonts, and the showcase still shows how to load your own.
- New: `./install.sh` installs junkslides as a command of its own, under `~/.local` or a `--prefix` you give, so you can run `junkslides serve` from any folder without building each time. `./install.sh --uninstall` removes it again.
- Improved: the readme no longer asks for `just`, which you never needed to run junkslides, and it has a section on removing junkslides with every file and folder it may leave behind.

## First release

0.1.0 · 2026-11-10 · `szonvzox::pwxvqpss`

- New: write a talk as cells in one text file, deck.md, and arrange the cells on the slide in a browser. Where a cell sits and how it looks is kept in layout.json under the cell's ID, so editing text never loses the layout and moving cells never touches the text.
- New: `junkslides init` creates a deck with default settings, theme and fonts, `junkslides serve` opens it in the editor at http://127.0.0.1:4870/, and `junkslides export` writes it as a page. From the project folder, `gleam run init`, `gleam run serve` and `gleam run export` do the same, and `just run` starts the last build without compiling.
- New: the cells pane, where you write each cell and move through the deck with modal keys: add, edit, split and merge cells, turn a cell into speaker notes, cut, copy and paste, start, move and delete slides, and undo and redo every change.
- New: the slide pane, where you drag a cell anywhere, also partly off the slide, resize it, nudge it with the keyboard, and pick a style variant and alignment. Drags and nudges snap to a step you choose in the status line or with `g` and `G`, from 120 down to 10 pixels or not at all, and junkslides remembers it for each deck.
- New: cells that do not fit their box are outlined and counted in the status line, and `X` removes the layout kept for deleted cells, as one step you can undo.
- New: edits you make to deck.md, theme.css or junkslides.toml in another editor show up at once. Every cell keeps its layout as long as its marker is there, and undo covers those edits too.
- New: while `deck.md` or `layout.json` is not being written, because the file has a mistake or a write failed, the status line says so until it is written again. A write that failed is tried again every second.
- New: headings, paragraphs and list items keep the line breaks and indentation you wrote.
- New: tables written as rows of pipes with a line of dashes under the header, where colons align a column. They have a quiet look in every theme, scale with a cell's variant, and a row that does not fit the header is noted under the cell.
- New: code blocks are highlighted by your own `tree-sitter` command and grammars; name the language after the opening fence, such as `haskell` or `hs`. Code in a language without a grammar is shaded by simple rules, and the `[code]` settings choose its keywords and comment markers and the languages always shaded that way.
- New: a line of attributes above a code block lights some of its lines (`lit="2 5-7"`) and marks words inside it between two characters you choose, such as `now="⟦⟧"`.
- New: mark words for your theme with a span and a class, such as `[2,040]{.now}`. Your theme lists the classes it knows in `--js-marks` and decides how they look, and a cell that uses another class gets a note.
- New: an image alone in its paragraph becomes a figure by its file. An `.svg` is drawn into the slide, where your theme's rules and fonts reach it; one with scripts, links to other files or anything but drawing markup is shown as a plain image. A `.json` is a chart drawn at the size of its cell, with lines, dots, stacked bars or bars and a switch between measures. An `.html` is a page of your own in a frame, such as an animation.
- New: a `junkslides.toml` in the deck's folder sets its fonts, colours, text size, line height, code size, slide numbers and margins without CSS. A change applies as soon as you save, and a mistake is named by its key while the last good settings stay.
- New: your `theme.css` comes after the settings and wins over them. It can use them as variables, such as `var(--js-accent)`, lists its style variants and marks, and can load fonts of its own from anywhere in the deck's folder.
- New: your theme can see where a slide sits in the talk, as `--js-index` and `--js-total`, and which slide is on screen, as `--js-here`, in the editor and in the exported page. An animation written for the slide on screen starts again each time you come to it.
- New: a new deck is set in et-book with code in Victor Mono, from its own `fonts/` folder, and the editor shows source text in Victor Mono too.
- New: every slide shows its number, as `01/12`, `01 / 12` or `01`, or not at all, and your theme can move or restyle it.
- New: press `E` or run `junkslides export` to write your deck as a folder you can open, host or zip, with your settings, theme, fonts and assets. The page has no scripts of its own and tells the browser to run none: arrow keys, space and Page Down step between slides, each slide fits the window, `#3` opens the third, and printing gives one slide per page. Speaker notes stay out, and so does any file outside the deck's folder, also one a symbolic link inside the deck leads to.
- New: press `F` or run `junkslides export --pdf` for a PDF with one slide per page, printed by Chrome, Chromium, Edge or Brave, whichever is found first, or by the program `JUNKSLIDES_CHROME` names. If printing fails, your last PDF stays as it was.
- New: the editor listens on your own machine only and accepts only its own page, so another site open in your browser cannot reach your deck. Its page runs no script but its own, and a deck's own pages and drawings opened from it run apart from it.
- New: an example deck in `examples/showcase`, a short talk about junkslides with a theme of its own that uses every feature. It shows where each slide is in the talk and grows a drawing each time you come to its slide, and it comes exported in `docs/`, a static page you can open or publish as it is, for example with GitHub Pages.
- New: junkslides is the name of what was called Zeno. For a deck made before, rename `zeno.toml` to `junkslides.toml`, and in `theme.css` write `js-` where it said `zeno-`, such as `.js-cell` and `var(--js-accent)`.
- New: junkslides is under the MIT licence.
