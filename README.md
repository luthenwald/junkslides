# junkslides

junkslides is a slide maker that keeps content and layout apart.

You write the content of a talk as cells in one text file, using a strict
djot-flavoured markdown dialect. You arrange, resize and restyle those cells
visually in a browser. junkslides remembers every layout edit in a separate
file, keyed by stable cell IDs, so content edits never lose layout and layout
edits never touch content.

## A deck on disk

```
talk/
  deck.md          content: slides and cells, with ID markers
  layout.json      placement and style per cell
  junkslides.toml  settings: fonts, colours, sizes, slide numbers
  theme.css        the look, in CSS, for anything the settings don't cover
  fonts/           font files of your own, if junkslides.toml or the theme names any
  assets/          images, referenced by paths relative to the deck
```

deck.md stays readable in any markdown viewer. Slides are separated by a `---`
line, and each cell and slide carries an ID in an HTML comment that junkslides
writes for you. You can edit deck.md in another editor while junkslides runs;
it picks up the change and keeps the layout of every cell it can still
recognise.
If a file you edited has a mistake junkslides cannot read, it keeps
what it had, stops writing that file, and says so in the status line until
the file reads again.

## Running it

junkslides is written in Gleam. With Gleam and Erlang installed, and
optionally the `tree-sitter` command for highlighting, install it from this
folder:

```sh
./install.sh                      # into ~/.local
./install.sh --prefix /opt/local  # or under a folder you choose
```

This builds junkslides once, copies the build to `<prefix>/lib/junkslides`
and writes the command `<prefix>/bin/junkslides`. Put `<prefix>/bin` on your
`PATH` if it is not there yet. Run the script again after you update the
project. Then, from any folder:

```sh
junkslides init ~/talks/lenses     # a new deck with default settings and theme
junkslides serve ~/talks/lenses    # then open http://127.0.0.1:4870/
junkslides export ~/talks/lenses   # a static page, see Exporting
```

Without installing, `gleam run init`, `gleam run serve` and `gleam run export`
do the same from this folder, building first each time. Run them from the
project's top folder or from `examples/`, since inside a package (`core`,
`server`, `client` and the others) `gleam run` runs that package instead.

The editor targets Chromium-based browsers for now.

## An example

`examples/showcase` is a short talk about junkslides, made with it. Each
slide uses something the editor can do: placed cells with their own
variants, code with lit lines and marks, a table, drawings, two charts, an
animation in a frame, and speaker notes that say what to look at. A rule
over each title has a dot that marks how far into the talk you are, drawn by
the showcase's own theme and switched off on its first slide, and the
drawing of the deck's folder grows each time you come to its slide. Open a
copy, so that your edits leave the example as it is:

```sh
cp -r examples/showcase ~/talks/showcase
junkslides serve ~/talks/showcase
```

Or export it straight away with
`junkslides export examples/showcase --out ~/showcase`.

You can also try the editor without installing anything. `docs/` holds a
copy of it that runs on the showcase with no server behind it, ready to be
served as it is, for example by GitHub Pages from the `docs` folder of the
main branch. There the deck lives in the page. Your browser keeps your
edits, so they are still there after a reload, and "start over" in the
status line forgets them. `E` gives you `deck.md` and `layout.json` as they
are at that moment, to save and open with junkslides on your own computer.

"open a folder" in the status line lets you pick a deck's folder from your
computer and work on a copy of it: `deck.md`, `layout.json`,
`junkslides.toml`, `theme.css` and the drawings and charts the deck names.
Nothing is written to the folder and nothing leaves your browser, which
keeps the copy until you close it. Pictures and font files are not copied,
so the page shows the deck without them. The picker needs Chrome, Edge or
another browser built on Chromium.

Code typed on the site is shaded by the simple rules, and a PDF needs the
real thing. The same talk as exported slides, with no script, is in
`docs/slides/`.

## The editor

The cells pane on the left holds the source of every cell; the slide pane on
the right draws the slide of the selected cell. Drag the divider to resize
them; `Ctrl-[` and `Ctrl-]` hide either one.

The keys are modal:

- Command mode: `j` and `k` move between cells, `o` adds a cell, `Enter`
  edits it, `J` and `K` move it, `b` starts a new slide, `t` turns a cell
  into speaker notes, `d`, `y` and `p` cut, copy and paste, `u` and `U` undo
  and redo. `d` on an empty slide deletes it, and `Ctrl-Shift-D` deletes the
  selected slide with all its cells (Control, also on a Mac).
- Edit mode: type, then `Esc`. A line that is exactly `---` starts a new
  slide; `Alt-Enter` splits the cell at the cursor.
- Canvas mode (`Tab` from the cells pane): drag a cell to place it, drag its
  corner to resize, arrows nudge, `Shift` with arrows resize, `f` returns it
  to the flow, `v` cycles the style variant, `a` the alignment, `g` and `G`
  make the snap step finer or coarser.
- In command and canvas mode, `n` hides the slide number on the selected
  slide and `.` hides the marks your theme draws on every slide, such as a
  rule or a progress dot. Press again to show them. The status line says
  what a slide has hidden.

Cells that are not placed stack in the theme's body area. Placed cells can
go anywhere, even partly off the slide. Drags and nudges snap to a step of
120, 60, 30, 20 or 10 pixels on the 1920 by 1080 slide, or to nothing at
all; pick it in the status line. Cells that do not fit their box get a
dashed outline, and the status line counts them.

Slides keep the lines of your text: a heading or paragraph written over
several lines shows over several lines, with the indentation you gave the
continued lines.

Code blocks are highlighted by [tree-sitter](https://tree-sitter.github.io/),
using the command and the grammars you have installed. Name the language after
the opening fence, such as `haskell` or `hs`: a grammar's name or one of its
file types both work. Without the command or a matching grammar, junkslides
shades the code by simple rules: comments, keywords from a list, capitalised
names, numbers and operators. The `[code]` settings choose the keywords and
comment markers, and can send a language to these rules even when it has a
grammar, which helps with excerpts that would not parse.

Words can be marked for the theme with a span and a class, such as
`[2,040]{.now}` or `[aside]{.quiet}`. The class says what the word is, and
the theme decides how it looks; it lists the classes it knows (see Themes),
and a cell that uses another one gets a note.

A code block can light some of its lines and mark words inside them, with one
line of attributes right above the fence:

````
{lit="2 5-7" now="⟦⟧"}
```gcl
x := e
assert p   ⟦and ask: is π ∧ ¬pθ satisfiable?⟧
```
````

`lit` lists the lines to light, counted from 1. Every other key is a mark
class with two characters that open and close it; the text between them is
drawn as that mark, and the two characters are left out. Pick characters the
code does not use.

An image alone in its paragraph becomes a figure when its file is one of
these:

- `.svg`: the drawing goes into the slide itself, so your theme's rules and
  fonts reach it. A drawing with scripts, event handlers, links to other
  files or markup that is not SVG is shown as a plain image instead, and
  junkslides tells you why.
- `.json`: a chart, drawn by junkslides at the size of its cell. The spec gives
  the kind (`lines`, `dots`, `stacked` or `bars`), the axes with their labels
  and log scales, and panels of series. A chart can hold several measures
  with a switch above it that shows one at a time.
- `.html`: a page of your own in a frame that fills the cell, with its
  script running, such as an animation. It runs apart from the editor and
  from the deck's other files. In the editor a press on it selects the cell;
  in the exported page you can use it.

A chart spec that does not read is drawn as a quiet box that says why.

A table is a block of pipe rows, with a header row and a line of dashes below it:

```
| Law    | Says                  | Holds |
|--------|-----------------------|------:|
| GetPut | put back what you got | yes   |
| PutPut | the last `put` wins   | no    |
```

Colons in the dashes align a column: `:---` to the start, `:--:` to the center,
`---:` to the end. Cells hold inline text such as `*strong*` and `` `code` ``;
write `\|` for a pipe in text. A row that does not fit the header is still drawn,
with a note under the cell. A table is as wide as its content and wraps at the
edge of its cell, and it scales with the cell's variant.

## Exporting

Press `E` in command mode, or run:

```sh
junkslides export ~/talks/lenses                     # into ~/talks/lenses/export
junkslides export ~/talks/lenses --out ~/site/lenses
junkslides export ~/talks/lenses --pdf               # and ~/talks/lenses/export/lenses.pdf
```

You get a folder with `index.html`, your settings as `settings.css` with the fonts they name, your `theme.css` with the fonts and other files it loads, and a copy of `assets/`, ready to open, host or zip. Licence files next to a font go with it. The page has no scripts of its own; an embedded `.html` figure runs its script inside its frame. Arrow keys, space and Page Down step between slides, and `#3` at the end of the address opens the third. Speaker notes stay out.

For a PDF with one slide per page, add `--pdf` or press `F` in command mode. junkslides prints the exported page with Chrome, Chromium, Edge or Brave, whichever it finds first; set `JUNKSLIDES_CHROME` to choose a program. If printing fails, your last PDF stays as it was. A CSS `filter` in your theme makes that element an image in the PDF, so its text can't be searched or copied.

Exporting again replaces those files and deletes nothing. If `junkslides.toml` has a mistake, nothing is exported until you fix it. junkslides tells you about images, fonts and theme files it could not find, and leaves out any outside the deck's folder, also those a symbolic link inside the deck leads to. The page is made for Chromium-based browsers, like the editor; elsewhere a slide may not scale to the window.

## Settings

`junkslides.toml` in the deck's folder holds the choices most decks change. A
new deck gets this one, and every line in it is optional:

```toml
[font.text]
family = "Charter"
fallback = 'Palatino, "Palatino Linotype", Georgia, serif'

[font.code]
family = "Menlo"
fallback = "ui-monospace, Consolas, monospace"

[palette]
background = "#fafafa"
text = "#222"
quiet = "#777"   # slide numbers and the quiet variant
accent = "#222"  # for your theme, as var(--js-accent)

[type]
size = 32        # pixels on a 1920 by 1080 slide
line-height = 1.4
code-scale = 1   # code size against its text, such as 0.875

[slide]
numbers = "01/12"  # or "01 / 12", "01", or "none"
margin = 2         # body inset in 60 px grid units, or [rows, columns]
gap = 24           # pixels between cells that flow

[code]
keywords = ["if", "then", "else", "do"]  # for code shaded by the simple rules
comments = ["--", "//"]                  # where a comment starts there
simple = []                              # languages always shaded that way
```

A new deck names fonts most systems have, with fallbacks for the others, so
it needs no font files. A family with no files is one installed on the
computer, so an exported page shows whichever font of the list its reader
has. A PDF always carries the fonts it was made with.

To use a font of your own, put its files anywhere in the deck's folder and
name them with paths relative to the deck. Give at least `family`; the faces
you leave out are made up by the browser. Exports and PDFs include the files,
with licence files next to them. The showcase does this with et-book and
Victor Mono in its `fonts/` folder.

```toml
[font.text]
family = "Inter"
fallback = "system-ui, sans-serif"
regular = "fonts/Inter-Regular.woff2"
bold = "fonts/Inter-Bold.woff2"
```

Colours are CSS colours, such as `"#1d1d1f"`, `"white"` or `"rgb(20 20 20 /
80%)"`. junkslides applies changes as soon as you save. If the file has a
mistake, such as a misspelt key, junkslides says which key and keeps the
settings it had.

## Themes

theme.css is plain CSS, and it comes after your settings, so any rule in it
wins. Slides are 1920 by 1080 pixels and are drawn as
`.js-slide`; the flowing cells sit in `.js-body` and every cell is a
`.js-cell`, with `data-variant` and `data-align` attributes for its style.
The slide number is `.js-page`, and code tokens carry classes such as
`.js-tok-keyword`, `.js-tok-string` and `.js-tok-comment`, named after
tree-sitter's highlight names. Tables are plain `table`, `th` and `td` elements,
drawn in shades of the text colour until your theme says otherwise; a column's
alignment is in the `data-align` attribute of its cells, and
`.js-cell table { width: 100%; }` makes tables fill their cells.
List the theme's variants and marks on `:root`:

```css
:root {
  --js-variants: "large small quiet emphasis";
  --js-marks: "now quiet";
}
.js-slide .now { color: var(--js-accent); }
```

A mark is a `span` with its classes, also inside code. A lit line of code is
`.js-lit`. Figures sit in `.js-figure`, and an inline drawing keeps the
classes it was drawn with, so `.js-figure .edge { stroke: … }` reaches its
lines. A chart is `.js-chart`, with its parts named `.js-chart-legend`,
`.js-chart-panel`, `.js-chart-xlabel` and so on, and its series and
markers carry the shade, shape and dash the spec gives them as classes.

Your settings are custom properties on `:root` that the theme can use, such
as `var(--js-accent)`, `var(--js-quiet)` and `var(--js-font-code)`.

Each slide knows its place in the talk: `--js-index` is its number and
`--js-total` the number of slides, so a mark can stand as far along a rule
as the slide is into the talk. The slide on screen also has `--js-here: 1`,
in the editor and in the exported page, and rules for it go in a container
query. An animation there starts again each time you come to its slide,
and a PDF shows the slide at rest:

```css
.js-slide { --at: calc((var(--js-index) - 1) / (var(--js-total) - 1)); }
.js-slide .progress { left: calc(var(--at) * 100%); }
@container style(--js-here: 1) {
  .js-figure .fan path { animation: grow 10s infinite; }
}
```

A slide can do without the furniture. When its number is switched off in
the editor it has `data-number="off"`, and the number is hidden for you.
When its marks are switched off it has `data-marks="off"`, which is for
your theme to honour, since only the theme knows what its marks are:

```css
.js-slide:not([data-marks="off"]) .progress { display: block; }
```

To leave the number off every slide, set `numbers = "none"` in
`junkslides.toml`. junkslides draws no progress mark of its own, so a deck
has one only if its theme draws it, as the showcase's does.

A theme can also load fonts itself, from anywhere in the deck's folder, with a
relative path that does not start with `/`. Exports and PDFs include them:

```css
@font-face {
  font-family: "Inter";
  src: url("fonts/Inter.woff2") format("woff2");
}
.js-slide { font-family: "Inter", sans-serif; }
pre, code { font-family: Menlo, monospace; }
```

Where neither your settings nor your theme name a font, the browser's default
is used.

junkslides reloads the theme when the file changes.

## Uninstalling

To remove junkslides completely:

1. Run `./install.sh --uninstall`, with the same `--prefix` if you gave one.
   It deletes the folder `<prefix>/lib/junkslides` and the command
   `<prefix>/bin/junkslides`, which is all the install script made. The
   default prefix is `~/.local`.
2. Delete `~/.config/junkslides/`. It holds one file, `view.json`, with the
   pane sizes and snap step the editor remembers for each deck.
3. Delete this project folder. Building leaves `build/` here and in `core`,
   `render`, `server`, `client`, `demo` and `e2e`, the editor's bundle in
   `server/priv/static/`, and a downloaded bundler in `client/.lustre/` and
   `demo/.lustre/`, all of which go with the folder.
4. If you used the editor on a published site, such as the copy in `docs/`,
   that site keeps your deck in your browser's local storage under the name
   `junkslides.deck`. "start over" or "close it" in the status line removes
   it, and so does clearing the site's data in your browser's settings.

Your decks are yours and stay where you made them. If a deck should go as
well, delete its folder: `deck.md`, `layout.json`, `junkslides.toml`,
`theme.css`, `fonts/`, `assets/`, and `export/` if you exported there. An
export made with `--out` is in the folder you named.

Two kinds of leftovers are possible if junkslides was stopped in the middle
of its work. A file named like `.deck.md.1a2b3c4d.js-tmp` in a deck's folder
is a write that did not finish, and folders or files named `js-pdf-*` and
`js-highlight-*` in the system's temporary folder (`$TMPDIR`, or `/tmp`)
belong to a PDF or highlighting run. All of them can be deleted.

junkslides keeps no caches or logs. Gleam, Erlang, tree-sitter and your
browser were installed by you and are left alone.

## License

MIT, see [license](license). The fonts that come with junkslides and its
examples have their own licences, which sit beside them.
