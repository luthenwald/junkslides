<!-- deck v1 -->

---
<!-- slide 019a7000-0000-7000-8000-000000000001 -->

<!-- cell 019a7000-0000-7000-8000-000000000002 -->
junkslides, a slide maker

<!-- cell 019a7000-0000-7000-8000-000000000003 -->
# ( content and layout,
kept apart )

<!-- cell 019a7000-0000-7000-8000-000000000004 -->
You write a talk as cells in one text file and arrange them on the slide in a browser. Each side keeps a file of its own, so neither can undo the other.

<!-- notes 019a7000-0000-7000-8000-000000000005 -->
This deck is the example that comes with junkslides. Every slide uses something the editor can do, and the notes say what to look at.

Here: three cells, each placed by hand. The kicker, the title and the sentence at the right have their own variants in theme.css.

From the next slide on, a rule runs over every title, with a dot at the slide's place in the talk.

---
<!-- slide 019a7000-0000-7000-8000-000000000006 -->

<!-- cell 019a7000-0000-7000-8000-000000000007 -->
![The deck folder](assets/folder.svg)

<!-- cell 019a7000-0000-7000-8000-000000000008 -->
{lit="2" now="⟦⟧" quiet="‹›"}
```
‹---›
<!-- slide ⟦019a7000-0000-7000-8000-000000000001⟧ -->

‹<!-- cell 019a7000-0000-7000-8000-000000000002 -->›
junkslides, a slide maker

‹<!-- cell 019a7000-0000-7000-8000-000000000003 -->›
# ( content and layout,
kept apart )
```

<!-- cell 019a7000-0000-7000-8000-000000000009 -->
on disk

## ( a deck is a folder )

<!-- cell 019a7000-0000-7000-8000-00000000000a -->
The first slide of this deck as it is written in deck.md. Every slide and cell carries an ID, which junkslides writes for you.

<!-- notes 019a7000-0000-7000-8000-00000000000b -->
The drawing on the left is an inline SVG. Its lines and labels take their colours and fonts from theme.css, and it grows branch by branch each time you come to this slide.

The code block lights the slide marker and marks its ID with a pair of brackets that are left out when it is drawn. The other markers are set quiet the same way.

---
<!-- slide 019a7000-0000-7000-8000-00000000000c -->

<!-- cell 019a7000-0000-7000-8000-00000000000d -->
deck.md

<!-- cell 019a7000-0000-7000-8000-00000000000e -->
{now="⟦⟧"}
```
<!-- cell ⟦019a7000-0000-7000-8000-000000000003⟧ -->
# ( content and layout,
kept apart )
```

<!-- cell 019a7000-0000-7000-8000-00000000000f -->
layout.json

<!-- cell 019a7000-0000-7000-8000-000000000010 -->
{now="⟦⟧"}
```json
"⟦019a7000-0000-7000-8000-000000000003⟧": {
   "place": {"x": 120, "y": 650, "w": 1640, "h": 290},
   "variant": "cover"
}
```

<!-- cell 019a7000-0000-7000-8000-000000000011 -->
the key

## ( layout is remembered by ID )

<!-- cell 019a7000-0000-7000-8000-000000000012 -->
Where a cell sits and how it looks is stored apart from its text, under the same ID.

<!-- notes 019a7000-0000-7000-8000-000000000013 -->
Two code cells placed side by side, each with a small label above it. The ID is marked in both, so the eye goes to the one thing they share.

layout.json is written by junkslides, in a fixed order, so a diff of it stays small.

---
<!-- slide 019a7000-0000-7000-8000-000000000014 -->

<!-- cell 019a7000-0000-7000-8000-000000000015 -->
![Cells before and after an outside edit](assets/rebase.svg)

<!-- cell 019a7000-0000-7000-8000-000000000016 -->
other editors

## ( outside edits keep the layout )

<!-- cell 019a7000-0000-7000-8000-000000000017 -->
Edit deck.md anywhere while junkslides runs. Each cell keeps its ID, and its layout goes with it.

<!-- notes 019a7000-0000-7000-8000-000000000018 -->
An outside editor moved the quote above the code and deleted the diagram. The lines join the same IDs before and after. The diagram's layout is kept as an orphan, so pasting it back brings its place back too. The new cell gets a fresh ID.

---
<!-- slide 019a7000-0000-7000-8000-000000000019 -->

<!-- cell 019a7000-0000-7000-8000-00000000001a -->
|    | Law                | Says                                                     |
|---:|--------------------|----------------------------------------------------------|
|  1 | Honest effects     | an op reports every ID it adds, retires or revives       |
|  2 | Unique IDs         | no two cells or slides share an ID                       |
|  3 | Invariants         | every deck an op can reach is well formed                |
|  4 | Round trip         | printing then parsing gives the same deck                |
|  5 | Undo               | undo and redo restore deck and layout exactly            |
|  6 | Layout coherence   | records belong to live IDs, the rest are orphans         |
|  7 | Valid placement    | every stored box keeps a part of itself on the slide     |
|  8 | Pure errors        | an op that fails changes nothing                         |
|  9 | Normalisation      | an edit never smuggles in a break or a marker            |
| 10 | Paste              | cut then paste brings back the ID and its layout         |

<!-- cell 019a7000-0000-7000-8000-00000000001b -->
the core

## ( ten laws, checked as properties )

<!-- cell 019a7000-0000-7000-8000-00000000001c -->
Each law runs on random decks and random sequences of edits, on Erlang and on JavaScript.

<!-- notes 019a7000-0000-7000-8000-00000000001d -->
A table in the dialect: a header, a line of dashes, and a colon that sets the first column to the right. The theme gives it a quieter rule and a wider first column.

---
<!-- slide 019a7000-0000-7000-8000-00000000001e -->

<!-- cell 019a7000-0000-7000-8000-00000000001f -->
![Script time while typing](assets/typing.json)

<!-- cell 019a7000-0000-7000-8000-000000000020 -->
a profile

## ( typing stays quick )

<!-- cell 019a7000-0000-7000-8000-000000000021 -->
Milliseconds of script for ten typed characters, before and after the probes were kept per slide.

<!-- notes 019a7000-0000-7000-8000-000000000022 -->
A chart drawn from a JSON spec, at the size of its cell. The bars are on a linear scale here; the spec can ask for a log one.

The numbers come from a profile of the editor in Chrome on decks of 60 and 150 slides.

---
<!-- slide 019a7000-0000-7000-8000-000000000023 -->

<!-- cell 019a7000-0000-7000-8000-000000000024 -->
![Tests by day](assets/tests.json)

<!-- cell 019a7000-0000-7000-8000-000000000025 -->
the first two weeks

## ( tested as it grew )

<!-- cell 019a7000-0000-7000-8000-000000000026 -->
Tests per package, counted at the end of each working day. The switch above the chart shows the browser checks.

<!-- notes 019a7000-0000-7000-8000-000000000027 -->
A lines chart with a grid of two rows. The switch is made of radio inputs and works in the exported page without a script. Click it.

---
<!-- slide 019a7000-0000-7000-8000-000000000028 -->

<!-- cell 019a7000-0000-7000-8000-000000000029 -->
{lit="1" now="⟦⟧"}
```gleam
pub fn apply(deck: Deck, op: Op, ⟦supply: IdSupply⟧) -> Applied

/// Only changes of identity.
pub type Effect {
   Fresh(cell: Id(CellTag), inherit_style: Option(Id(CellTag)))
   Retired(cell: Id(CellTag))
   Revived(cell: Id(CellTag))
   SlideFresh(slide: Id(SlideTag))
   SlideRetired(slide: Id(SlideTag))
}
```

<!-- cell 019a7000-0000-7000-8000-00000000002a -->
No clock, no randomness, no files. New IDs come from a supply passed in, so an edit can be replayed after an outside change and give the same IDs.

<!-- cell 019a7000-0000-7000-8000-00000000002b -->
gleam

## ( the core is pure )

<!-- notes 019a7000-0000-7000-8000-00000000002c -->
Code shaded by the simple rules, since Gleam has no tree-sitter grammar: keywords from junkslides.toml, capitalised names, comments and punctuation. The first line is lit, and the supply is marked.

---
<!-- slide 019a7000-0000-7000-8000-00000000002d -->

<!-- cell 019a7000-0000-7000-8000-00000000002e -->
Content edits never lose [layout]{.now}.
Layout edits never touch [content]{.now}.
    [And both are undone with u.]{.quiet}

<!-- cell 019a7000-0000-7000-8000-00000000002f -->
marks

## ( words marked for the theme )

<!-- cell 019a7000-0000-7000-8000-000000000030 -->
A span with a class says what a word is. The theme lists the classes it knows and decides how they look.

<!-- notes 019a7000-0000-7000-8000-000000000031 -->
The three lines are one paragraph written over three lines, and the slide keeps them so, with the indent of the third.

---
<!-- slide 019a7000-0000-7000-8000-000000000043 -->

<!-- cell 019a7000-0000-7000-8000-000000000044 -->
{lit="2 5" now="⟦⟧"}
```css
.js-slide {
   --at: calc((var(⟦--js-index⟧) - 1) / (var(⟦--js-total⟧) - 1));
}
.js-cell[data-variant="title"]::after {
   left: calc(var(--at) * 1680px);
}
@container style(⟦--js-here⟧: 1) {
   .folder .branch { animation: grow 10s infinite; }
}
```

<!-- cell 019a7000-0000-7000-8000-000000000045 -->
Watch the dot over this title: it moves one step on every slide. On the slide with the folder, the tree grows each time you come to it, and stands still in the PDF.

<!-- cell 019a7000-0000-7000-8000-000000000046 -->
theme variables

## ( the theme knows where it is )

<!-- cell 019a7000-0000-7000-8000-000000000047 -->
Every slide carries its number and the count, and the slide on screen says so. The rule and the growing tree are CSS alone.

<!-- notes 019a7000-0000-7000-8000-000000000048 -->
Three custom properties that junkslides sets on every slide: its number, the number of slides, and whether it is the one on screen. The code is an excerpt of this deck's theme.css.

In the exported page there is no script: the slide the page has snapped to is the one on screen. In the editor it is the slide in the pane.

---
<!-- slide 019a7000-0000-7000-8000-000000000032 -->

<!-- cell 019a7000-0000-7000-8000-000000000033 -->
![Cells settling into place](assets/settle.html)

<!-- cell 019a7000-0000-7000-8000-000000000034 -->
canvas

## ( from the flow into place )

<!-- cell 019a7000-0000-7000-8000-000000000035 -->
Cells that are not placed flow down the body area. Drag one and it keeps its box; press `f` and it flows again.

<!-- notes 019a7000-0000-7000-8000-000000000036 -->
An embedded page of our own, assets/settle.html, drawn with CSS animations only. It runs in a sandboxed frame and loops while the slide is on screen.

---
<!-- slide 019a7000-0000-7000-8000-000000000037 -->

<!-- cell 019a7000-0000-7000-8000-000000000038 -->
### command

- `j` `k` move between cells
- `o` adds a cell, `b` a slide
- `Enter` edits, `t` makes notes
- `d` `y` `p` cut, copy, paste
- `u` `U` undo and redo

<!-- cell 019a7000-0000-7000-8000-000000000039 -->
### edit

- type, then `Esc`
- a line of `---` starts a slide
- `Alt-Enter` splits the cell

<!-- cell 019a7000-0000-7000-8000-00000000003a -->
### canvas

- drag to place, corner to resize
- arrows nudge, with `Shift` resize
- `v` variant, `a` alignment
- `f` back into the flow
- `g` `G` finer or coarser snap

<!-- cell 019a7000-0000-7000-8000-00000000003b -->
the editor

## ( three modes )

<!-- cell 019a7000-0000-7000-8000-00000000003c -->
`Tab` moves between the cells pane and the slide.

<!-- notes 019a7000-0000-7000-8000-00000000003d -->
Three lists, placed as columns. The keys are inline code.

---
<!-- slide 019a7000-0000-7000-8000-00000000003e -->

<!-- cell 019a7000-0000-7000-8000-00000000003f -->
```sh
gleam run init ~/talks/lenses     # a new deck
gleam run serve ~/talks/lenses    # the editor, on port 4870
gleam run export ~/talks/lenses --pdf
```

<!-- cell 019a7000-0000-7000-8000-000000000040 -->
The export is a folder with one page, your theme and your assets. Arrow keys step through it, and printing gives one slide per page.

<!-- cell 019a7000-0000-7000-8000-000000000041 -->
to try it

## ( one folder, one page, one PDF )

<!-- notes 019a7000-0000-7000-8000-000000000042 -->
Speaker notes like this one stay out of the export.
