# 02/10 File format

## The deck folder

```
talk/
  deck.md
  layout.json
  theme.css
  assets/
```

- A deck is a folder. Zeno is started on the folder, not on a file.
- `deck.md` and `layout.json` are written by Zeno. `deck.md` may also be edited
  by hand; `layout.json` normally is not.
- `theme.css` is written by the user (Zeno can create a default one).
- All paths inside cells (images) are relative to the deck folder. Paths that
  resolve outside the deck folder are rejected by the server when serving.
- Per-user view state (pane sizes, hidden panes) is not part of the deck; see
  06-runtime.md.

## deck.md

### Example

```markdown
<!-- deck v1 -->

---
<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e01 -->

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e02 -->
# Why lenses

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e03 -->
A lens is a pair of functions, _get_ and _put_,
satisfying a few round-trip laws.

<!-- notes 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e04 -->
Mention Boomerang here.

---
<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e05 -->

<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e06 -->
![A lens diagram](assets/lens.png)
```

The file still reads well in any ordinary markdown viewer: markers are
invisible comments and breaks show as horizontal rules.

### Structural lines

A structural line is a line that matches one of these exactly (no leading or
trailing whitespace):

| Line | Meaning |
|---|---|
| `<!-- deck v1 -->` | Header. Format version of the dialect |
| `---` | Slide break |
| `<!-- slide UUID -->` | Slide marker; only valid directly after a break |
| `<!-- cell UUID -->` | Content cell marker |
| `<!-- notes UUID -->` | Notes cell marker |
| `<!-- cell -->` | Content cell marker without ID (hand-written) |
| `<!-- notes -->` | Notes cell marker without ID (hand-written) |

UUID is a lowercase RFC 9562 UUID in the standard 36-character form. Zeno
generates version 7; the reader accepts any valid version.

Structural lines are recognised everywhere, including inside fenced code. This
is deliberate: an unclosed code fence in one cell can never swallow the cells
after it. The cost is that a cell body cannot contain a line that is exactly
`---` or exactly a marker. See "Editing rules" below for how the editor handles
that.

### Grammar (informal)

```
deck         ::= header? preamble? slide*
header       ::= "<!-- deck v1 -->"
preamble     ::= body                       (text before the first break)
slide        ::= break slide-marker? item*
break        ::= "---"
slide-marker ::= "<!-- slide " UUID " -->"
item         ::= cell-marker body | body
cell-marker  ::= "<!-- cell " UUID " -->"
               | "<!-- notes " UUID " -->"
               | "<!-- cell -->"
               | "<!-- notes -->"
body         ::= all lines up to the next structural line
```

### Reading rules

Markers are optional on read. The reader turns any valid file into a deck, and
assigns fresh IDs wherever they are missing:

1. A missing header means version 1.
2. A non-empty preamble (text before the first break) becomes an implicit first
   slide with a fresh slide ID. An empty file is a deck with one empty slide.
3. A break without a slide marker gets a fresh slide ID.
4. A cell marker without an ID gets a fresh cell ID, with the marker's kind.
5. Unmarked text (text after a slide marker or break, before the first cell
   marker of that slide) becomes one new content cell per top-level block
   (paragraph, heading, list, code block, quote). This makes importing an
   existing markdown file useful.
6. A marked cell's body is the text between its marker and the next structural
   line, with leading and trailing blank lines removed.
7. Duplicate IDs: the first occurrence keeps the ID, every later occurrence
   gets a fresh one. This happens when text is copied in an outside editor.
8. A slide marker that does not directly follow a break is an error.
9. An unknown header version is an error.

Errors are reported with a line number. On error, Zeno keeps its last good
state and does not write the file (see 06-runtime.md).

### Printing rules

The printer is canonical; the same deck always prints to the same bytes.

1. The header line, then a blank line.
2. For each slide: `---`, the slide marker, a blank line.
3. For each cell: its marker, its body, a blank line.
4. Exactly one blank line between items, no trailing whitespace, LF line
   endings, the file ends with a single newline.
5. Every slide and cell gets a marker with its ID.

Round-trip requirements (tested as laws, see 03-data-model.md):

- `parse(print(d)) == d` for every deck `d` reachable through operations.
- `print(parse(s)) == s` for every string `s` produced by `print`.

### Editing rules that protect the structure

Because structural lines cannot appear inside a body, the editor normalises
text before it becomes an operation (the function `normalize_edit` in core):

- A line that is exactly `---` typed into a cell means "start a new slide
  here". The edit becomes: split the cell at that line, then insert a break
  before the second part. The `---` line itself is dropped. This holds even
  inside a code fence; the result is visible and easy to fix.
- A line that is exactly a marker is rejected. The cell shows an error and the
  edit is not sent until the line is changed.

## The cell dialect

Cell bodies use djot syntax, restricted so that every construct has one
spelling and every cell is self-contained. Notes cells use the same dialect.

### Allowed blocks

- Paragraphs.
- Headings with `#` to `######` (djot: no setext headings exist).
- Bullet lists with `-`, ordered lists with `1.`. Nested lists follow djot's
  rule of a blank line before a sublist.
- Fenced code blocks with three backticks, optional language.
- Block quotes with `>`.
- An image on its own line.

Blocks are separated by blank lines (a djot rule; headings are always followed
by a blank line).

### Allowed inline syntax

- `_emphasis_` and `*strong*` (djot).
- `` `code` ``.
- Inline links `[text](url)` and images `![alt](path)`.
- Backslash escapes and hard line breaks with a trailing backslash (djot).

### Forbidden in the prototype

- Thematic breaks of any spelling (`---`, `***`, `* * *`): `---` is reserved
  for slide breaks.
- Raw HTML and raw blocks or inlines.
- Reference-style links and reference definitions, and footnotes: they would
  connect cells to each other.
- Attributes (`{.class}`, `{#id}`) and divs (`:::`): they would bring layout
  back into content.
- Tables, definition lists, math: possible later.

Forbidden constructs inside a cell do not break the file (they are not
structural). They are reported as cell diagnostics and rendered as plain text.

## layout.json

### Example

```json
{
  "version": 1,
  "cells": {
    "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e02": {
      "place": { "col": 2, "row": 1, "w": 28, "h": 3 },
      "variant": "large",
      "align": "start"
    },
    "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e03": {
      "variant": "quiet"
    }
  },
  "slides": {},
  "orphans": [
    {
      "kind": "cell",
      "id": "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e07",
      "record": { "variant": "large" },
      "retired_at": "2026-10-27T14:03:00Z"
    }
  ]
}
```

### Fields

| Field | Meaning |
|---|---|
| `version` | Schema version, currently 1. Unknown versions are an error |
| `cells` | Map from cell ID to cell record. Only live cells |
| `cells.*.place` | Optional grid area: `col` 0..31, `row` 0..17, `w` 1..32, `h` 1..18, with `col + w <= 32` and `row + h <= 18`. Absent means the cell flows in the body area |
| `cells.*.variant` | Optional theme variant name |
| `cells.*.align` | Optional `start`, `center` or `end` |
| `slides` | Map from slide ID to slide record. Reserved; empty in the prototype |
| `orphans` | Records whose cell or slide is not live, with retirement time |

A cell record with no fields is not stored. Records are written with keys in
sorted order so diffs stay small.

### Consistency on load

When Zeno loads a deck, any record in `cells` or `slides` whose ID is not live
in deck.md moves to `orphans`; any orphan whose ID is live again moves back.
This also repairs the files after a crash between writing deck.md and
layout.json.
