# S5 jot

## Question

Does `jot` run on the JavaScript target, cover the allowed constructs, and
expose enough structure to reject forbidden ones? Use it as is, wrap it, or
write a small parser for the subset?

## What was tried

`spikes/s5_jot`, with jot 12.1.2 (deps: houdini 1.2.1, splitter 1.3.0),
Gleam 1.19.2, OTP 29, node 26.

- `src/corpus.gleam`: one small cell body per allowed and per forbidden
  construct.
- `src/probe.gleam`, `src/probe2.gleam`: print jot's AST and HTML for the
  corpus and for edge cases (`gleam run -m probe`, on either target).
- `src/check.gleam`: a prototype wrapper that walks the AST and lists the
  dialect problems it can see.
- `src/blocks.gleam`: a line-based splitter for reading rule 5.
- `test/s5_jot_test.gleam`: classification of the corpus, and the splitter
  checked against jot.

Run with `just s5` (both targets).

## Results

jot is pure Gleam and gives the same AST on Erlang and JavaScript (the probe
output differs only in how `string.inspect` prints record labels).

### Allowed constructs

| Construct | Result |
|---|---|
| Paragraph, headings 1 to 6 | `Paragraph`, `Heading(level)`. Headings get an automatic `id` attribute and an entry in `references` |
| Bullet list `-`, ordered list `1.` | `BulletList(style: BulletDash)`, `OrderedList(FullStop, NumericOrdinal, start)`, tight or loose |
| Nested list after a blank line | Nested correctly |
| Fenced code, with and without language | `Codeblock(language)`. An unclosed fence runs to the end of the text, which is harmless inside one cell |
| Block quote | `BlockQuote` |
| Image on its own line | `Paragraph([Text(""), Image(...)])` |
| `_em_`, `*strong*`, code, links, inline images | `Emphasis`, `Strong`, `Code`, `Link(Url)`, `Image(Url)` |
| Escapes, hard break | Correct, `Linebreak` |

Every allowed construct is covered.

### Forbidden constructs

| Construct | What jot does | Visible to a walker |
|---|---|---|
| Thematic break (`---`, `***`, `* * *`) | `ThematicBreak` | yes |
| Raw block (```` ``` =html ````) | `RawBlock`, and `to_html` emits it unescaped | yes |
| Raw HTML inline (`<b>`) | Literal text, escaped in HTML | not needed, already plain text |
| Raw inline (`` `x`{=html} ``) | Not supported: code plus literal text | not needed |
| Reference link | `Link(Reference(..))` | yes |
| Reference definition | Entry in `Document.references`, mixed with heading ids | yes, by excluding heading ids |
| Footnote | `Footnote` inline and `Document.footnotes` | yes |
| Block attributes `{.big}` | Non-empty `attributes` on the block | yes |
| Inline attributes `_x_{.big}`, stray `{.x}` | Silently dropped | no |
| Div `:::` | `Div` | yes |
| Span `[x]{.big}` | `Span` | yes |
| Math | `MathInline`, `MathDisplay` | yes |
| Tables, definition lists | Not supported: rendered as plain paragraphs | not needed |
| Setext heading | Not djot: a plain paragraph | not needed |
| `*` and `+` bullets, `1)` and `a.` ordinals | Accepted, with the style recorded | yes (spelling) |
| djot extras outside the dialect list: `^sup^`, `~sub~`, `{-del-}`, `{+ins+}`, `:symbol:`, non-breaking space | Own inline nodes | yes |

### Problems found in jot

- `{=mark=}` at the start of a paragraph is read as a block attribute with an
  empty key and renders as `<p ="mark=">`, which is broken HTML, and the
  text is lost. In the middle of a paragraph the text also disappears.
- Inline attributes and stray `{...}` are dropped without a trace.
- `to_html` does not escape raw blocks and keeps `javascript:` URLs.
- Smart punctuation is always on: `--` becomes an en dash and `---` an em
  dash inside text. This is djot behaviour, not a bug.
- The AST has leading `Text("")` nodes (jot's own TODO: collapse adjacent
  text nodes). Harmless.
- No source positions. The AST cannot tell where a block starts in the text.

### Reading rule 5 (one cell per top-level block)

jot cannot split text into blocks by itself, because it has no source spans.
`blocks.gleam` does it by lines instead. Blank lines separate blocks, except
inside a code fence and between items or indented continuations of the same
list. Tested against jot as the oracle: every chunk parses to exactly one
top-level block, and the chunk count equals jot's block count for the whole
text. The cases covered are loose and tight lists, nested lists, fences with
blank lines (also inside list items), longer fences, quotes and lazy lines.
It is about 100 lines, pure, and works on both targets.

## What to use

Wrap jot. The core gets a `dialect` module that:

1. Parses a cell body with `jot.parse`.
2. Walks the AST and reports diagnostics as in `check.gleam`: the forbidden
   nodes, non-default list spellings, attributes other than the heading `id`,
   reference destinations and definitions, and footnotes.
3. Never uses `jot.to_html`. The client renders the AST into Lustre elements
   itself. That avoids raw HTML injection, allows URL sanitising (relative
   paths, `http`, `https` and `mailto` only), and renders a forbidden node as
   its plain text (`jot.inner_text` for blocks).
4. Adds a small source-level check for what jot drops silently. Flagging a
   `{` that directly follows a non-space character or begins a line, outside
   code, covers inline attributes, stray attributes and `{=mark=}`.

Use `blocks.gleam`, or its successor in `core/src/zeno/file.gleam`, for
reading rule 5. It does not depend on jot.

Writing an own parser for the subset is not needed. Pin jot to 12.x. If jot
changes its AST, the walker breaks at compile time, which is what we want.

## Consequences for the design

- P19 (`jot` for cell bodies) stands.
- 02-file-format.md: "Forbidden constructs inside a cell ... are rendered as
  plain text" holds when the renderer works on the AST. The djot extras
  (super and subscript, insert, delete, mark, symbols) should be named in the
  forbidden list, since they are neither allowed nor listed now.
- 07-stack.md: `jot` moves from candidate to chosen, used through a wrapper
  that does not use `to_html`.

## Open decisions

- Whether the djot extras should be forbidden (my proposal) or allowed. They
  add one spelling each, so they do not break the one-spelling rule, but they
  are not in the list in 02-file-format.md.
- Whether to report the `{=mark=}` bug upstream.
