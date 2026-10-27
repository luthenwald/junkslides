# Zeno

Zeno is a slide maker that keeps content and layout apart.

You write the content of a talk as cells in one text file, using a strict
djot-flavoured markdown dialect. You arrange, resize and restyle those cells
visually in a browser. Zeno remembers every layout edit in a separate file,
keyed by stable cell IDs, so content edits never lose layout and layout edits
never touch content.

Status: the design for the first prototype is complete. No code exists yet.

## The idea in one page

- Two owners. The text file owns content. The layout file owns placement and
  style. The theme CSS owns the default look.
- Cells. A cell is a piece of markdown that becomes one component on a slide.
  You choose cell boundaries, so they are also layout boundaries.
- Identity by operation. Cells are edited in Zeno's own two-pane editor, so
  every edit knows which cell it touches. Nothing is guessed from text diffs.
- Machine-maintained markers. Each cell and slide carries a UUIDv7 in an HTML
  comment. The editor writes and hides them. Markers are optional when reading
  (a hand-written file works) and always present when writing.
- Layout follows identity. If an ID survives an operation, the cell's layout
  survives with it.
- A 32x18 grid on a fixed 16:9 slide. Unplaced cells flow in a body area;
  placed cells sit at explicit grid coordinates.
- Gleam everywhere. A Gleam server (Erlang target) owns the state and the
  files; a Lustre client (JavaScript target) is the editor. They share one
  core package. No handwritten JavaScript or TypeScript.

## A deck on disk

```
talk/
  deck.md        content: slides and cells, with ID markers
  layout.json    placement and style per cell, plus orphans
  theme.css      the default look
  assets/        images, referenced by paths relative to the deck
```

## Documents

| File | Contents |
|---|---|
| [CLAUDE.md](CLAUDE.md) | Instructions for coding agents working on Zeno |
| [docs/01-overview.md](docs/01-overview.md) | Goals, non-goals, principles, glossary |
| [docs/02-file-format.md](docs/02-file-format.md) | Deck folder, deck.md grammar, the dialect, layout.json |
| [docs/03-data-model.md](docs/03-data-model.md) | Types, operations, effects, identity rules, laws |
| [docs/04-layout.md](docs/04-layout.md) | Grid, flow area, placement, variants, overflow, orphans, theme contract |
| [docs/05-editor.md](docs/05-editor.md) | Panes, modes, keymap, undo, selection, visual style |
| [docs/06-runtime.md](docs/06-runtime.md) | Server, protocol, writes, watching, external edits |
| [docs/07-stack.md](docs/07-stack.md) | Gleam, packages, project layout, testing |
| [docs/08-roadmap.md](docs/08-roadmap.md) | Prototype scope, spikes, milestones, later work |
| [docs/09-decisions.md](docs/09-decisions.md) | Decision log and open questions |
| [docs/10-references.md](docs/10-references.md) | Related work and reading |
