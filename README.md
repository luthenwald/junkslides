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
  fonts/           the fonts junkslides.toml names
  assets/          images, referenced by paths relative to the deck
```

deck.md stays readable in any markdown viewer. Slides are separated by a `---`
line, and each cell and slide carries an ID in an HTML comment that junkslides
writes for you. You can edit deck.md in another editor while junkslides runs;
it picks up the change and keeps the layout of every cell it can still
recognise.

## Running it

junkslides is written in Gleam. With Gleam, Erlang and `just` installed, and
optionally the `tree-sitter` command for highlighting, from this folder:

```sh
gleam run init ~/talks/lenses     # a new deck with default settings and theme
gleam run serve ~/talks/lenses    # then open http://127.0.0.1:4870/
gleam run export ~/talks/lenses   # a static page, see Exporting
```

`gleam run` builds junkslides and the editor first. Relative folders are read
from where you run it, which can be any folder of this project except the
packages inside it (`core`, `server`, `client` and the others), where it runs
that package instead.

`just junkslides serve ~/talks/lenses` does the same from any folder of the
project, and `just run serve ~/talks/lenses` starts the last `just junkslides`
build straight away.

The editor targets Chromium-based browsers for now.

## An example

`examples/showcase` is a short talk about junkslides, made with it. Each
slide uses something the editor can do: placed cells with their own
variants, code with lit lines and marks, a table, drawings, two charts, an
animation in a frame, and speaker notes that say what to look at. Open a
copy, so that your edits leave the example as it is:

```sh
cp -r examples/showcase ~/talks/showcase
gleam run serve ~/talks/showcase
```

Or export it straight away with
`gleam run export examples/showcase --out ~/showcase`.

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
  fonts reach it. A drawing with scripts, event handlers or links to other
  files is shown as a plain image instead, and junkslides tells you why.
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
gleam run export ~/talks/lenses                     # into ~/talks/lenses/export
gleam run export ~/talks/lenses --out ~/site/lenses
gleam run export ~/talks/lenses --pdf               # and ~/talks/lenses/export/lenses.pdf
```

You get a folder with `index.html`, your settings as `settings.css` with the fonts they name, your `theme.css` with the fonts and other files it loads, and a copy of `assets/`, ready to open, host or zip. Licence files next to a font go with it. The page has no scripts of its own; an embedded `.html` figure runs its script inside its frame. Arrow keys, space and Page Down step between slides, and `#3` at the end of the address opens the third. Speaker notes stay out.

For a PDF with one slide per page, add `--pdf` or press `F` in command mode. junkslides prints the exported page with Chrome, Chromium, Edge or Brave, whichever it finds first; set `JUNKSLIDES_CHROME` to choose a program. If printing fails, your last PDF stays as it was. A CSS `filter` in your theme makes that element an image in the PDF, so its text can't be searched or copied.

Exporting again replaces those files and deletes nothing. If `junkslides.toml` has a mistake, nothing is exported until you fix it. junkslides tells you about images, fonts and theme files it could not find, and leaves out any outside the deck's folder. The page is made for Chromium-based browsers, like the editor; elsewhere a slide may not scale to the window.

## Settings

`junkslides.toml` in the deck's folder holds the choices most decks change. A
new deck gets this one, and every line in it is optional:

```toml
[font.text]
family = "et-book"
fallback = 'Palatino, "Palatino Linotype", "Book Antiqua", Georgia, serif'
regular = "fonts/et-book-roman.woff2"
italic = "fonts/et-book-italic.woff2"
bold = "fonts/et-book-bold.woff2"

[font.code]
family = "Victor Mono"
fallback = "ui-monospace, Menlo, Consolas, monospace"
regular = "fonts/victor-mono-regular.woff2"
italic = "fonts/victor-mono-italic.woff2"
bold = "fonts/victor-mono-bold.woff2"

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

To use another font, put its files anywhere in the deck's folder and name them
with paths relative to the deck. Give at least `family`; the faces you leave
out are made up by the browser. A family with no files is one installed on
your computer, which works only there. Exports and PDFs include the files,
with licence files next to them.

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
