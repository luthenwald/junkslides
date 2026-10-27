# 09/10 Decisions

Decisions are not changed during implementation without asking. If the
implementation shows a decision is wrong, write it up (what, why, options) and
ask.

## Decided

| ID | Decision | Rationale |
|---|---|---|
| D01 | Content in a text file, default look in a CSS theme, visual layout edits remembered separately | Content and layout have different owners |
| D02 | Edit content as cells in Zeno's own UI rather than relying on free-form markdown editing | Identity carried by operations is reliable; identity inferred from text diffs is error-prone |
| D03 | deck.md is markdown-like text with machine-maintained ID markers in HTML comments | Readable, diffable, renders in ordinary viewers; external edits stay simple to reconcile |
| D04 | A page break is a `---` line; typing `---` in a cell starts a new slide | Natural to write; matches the original idea |
| D05 | A strict, unambiguous dialect: no `---` horizontal rule, no setext headings, one spelling per construct | Removes ambiguity at the source |
| D06 | Djot syntax as the base of the dialect, including inline marks (`_emphasis_`, `*strong*`) | Djot was designed to remove markdown's ambiguities |
| D07 | UUID IDs, generated as UUIDv7 | Unique without coordination; v7 sorts by creation time |
| D08 | Cells are just markdown (no subtypes), plus a speaker-notes kind, cycled with a shortcut | Simple model; notes stay with their slide |
| D09 | Asset paths are relative to the deck | Decks are movable folders |
| D10 | Identity rules per operation are encoded in the types as far as Gleam allows, the rest as property laws | Correctness of the core is the whole point |
| D11 | Groups of cells are deferred | Not needed for the prototype |
| D12 | Web UI with a cells pane and a slide pane, a draggable divider, either pane hideable | Content and layout side by side |
| D13 | Runtime is a local server plus a browser, with external-edit watching, debounced writes and atomic writes | Files are owned by one process; outside editors remain usable |
| D14 | A 32x18 grid on a fixed 16:9 slide | Square grid units, integer coordinates, calm alignment |
| D15 | Gleam for server, client and shared core; no Haskell, no Rust, no handwritten JS or TS | Typed, one language on both sides |
| D16 | Presenting and export come after the prototype | Focus on the editing loop first |

## Defaults chosen while writing the design (please review)

These follow from the discussion but were not individually confirmed. They
are the working assumptions for implementation until changed.

| ID | Default | Where |
|---|---|---|
| P01 | A deck is a folder: deck.md, layout.json, theme.css, assets/ | 02 |
| P02 | Only `---` is a break; `***` is not accepted | 02 |
| P03 | The break carries the slide ID (a slide marker right after `---`); the file begins with a break | 02 |
| P04 | Marker syntax `<!-- cell UUID -->`, `<!-- notes UUID -->`, `<!-- slide UUID -->`, `<!-- deck v1 -->`, plus ID-less `<!-- cell -->` and `<!-- notes -->` for hand-written files | 02 |
| P05 | Markers optional on read, always written; unmarked text becomes one cell per top-level block | 02 |
| P06 | Structural lines are recognised even inside code fences, so a cell cannot contain a line that is exactly `---` or a marker | 02 |
| P07 | A paste reuses the ID if and only if it is not live (cut and paste is a move, copy and paste is a copy) | 03 |
| P08 | Split: the first part keeps the ID; the second inherits variant and alignment, not placement. Duplicate likewise | 03 |
| P09 | Moving a cell to another slide keeps its placement | 03, 04 |
| P10 | Per-cell placement: unplaced cells flow in a theme-defined body area, placed cells have grid areas; no per-slide mode | 04 |
| P11 | Style is a theme variant plus alignment; no free-form CSS | 04 |
| P12 | Overflow is flagged, never clipped or shrunk | 04 |
| P13 | Orphaned layout records are kept until an explicit purge | 04 |
| P14 | Undo by bounded snapshots (500), text edits coalesced per cell within one second, external edits are steps | 03 |
| P15 | View state stored by the server in `~/.config/zeno/view.json` | 05 |
| P16 | Modal keymap as listed in 05-editor.md | 05 |
| P17 | Full-state broadcast over WebSocket; server bound to 127.0.0.1, port 4870 | 06 |
| P18 | Polling watcher (`polly`) for the prototype | 06, 07 |
| P19 | `jot` for cell bodies, pending spike S5 | 07 |
| P20 | Slide numbers shown as `01/12` | 05 |

## Open questions

| ID | Question | Notes |
|---|---|---|
| Q01 | How should a title area work (which cell goes there, if any)? | Prototype has only a body area |
| Q02 | Which variants should the default theme offer? | Prototype: large, small, quiet, emphasis |
| Q03 | Which constructs join the dialect next: tables, math, footnotes? | Footnotes conflict with cell independence |
| Q04 | Should undo history survive restarts? | Prototype: no |
| Q05 | Presenting: in the editor, from exported HTML, or both? | After the prototype |
| Q06 | Should empty slides be allowed in presentation output? | They are allowed in the deck |
