# Zeno

Zeno is a slide maker that keeps content and layout apart.

You write the content of a talk as cells in one text file, using a strict
djot-flavoured markdown dialect. You arrange, resize and restyle those cells
visually in a browser. Zeno remembers every layout edit in a separate file,
keyed by stable cell IDs, so content edits never lose layout and layout edits
never touch content.

## A deck on disk

```
talk/
  deck.md        content: slides and cells, with ID markers
  layout.json    placement and style per cell
  theme.css      the default look
  assets/        images, referenced by paths relative to the deck
```

deck.md stays readable in any markdown viewer. Slides are separated by a
`---` line, and each cell and slide carries an ID in an HTML comment that
Zeno writes for you. You can edit deck.md in another editor while Zeno runs;
it picks up the change and keeps the layout of every cell it can still
recognise.

## Running it

Zeno is written in Gleam. With Gleam, Erlang and `just` installed, from
this folder:

```sh
just zeno init ~/talks/lenses     # a new deck with the default theme
just zeno serve ~/talks/lenses    # then open http://127.0.0.1:4870/
```

The editor targets Chromium-based browsers for now.

## The editor

The cells pane on the left holds the source of every cell; the slide pane on
the right draws the slide of the selected cell. Drag the divider to resize
them; `Ctrl-[` and `Ctrl-]` hide either one.

The keys are modal:

- Command mode: `j` and `k` move between cells, `o` adds a cell, `Enter`
  edits it, `J` and `K` move it, `b` starts a new slide, `t` turns a cell
  into speaker notes, `d`, `y` and `p` cut, copy and paste, `u` and `U` undo
  and redo.
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
continued lines. Code blocks are highlighted for the language named after
the opening fence, such as `haskell`, `gleam` or `python`.

## Themes

theme.css is plain CSS. Slides are 1920 by 1080 pixels and are drawn as
`.zeno-slide`; the flowing cells sit in `.zeno-body` and every cell is a
`.zeno-cell`, with `data-variant` and `data-align` attributes for its style.
The slide number is `.zeno-page`, and code tokens carry classes such as
`.zeno-tok-keyword`, `.zeno-tok-string` and `.zeno-tok-comment`.
List the theme's variants on `:root`:

```css
:root { --zeno-variants: "large small quiet emphasis"; }
```

Zeno reloads the theme when the file changes.
