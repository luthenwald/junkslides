# 08/10 Roadmap

## Prototype scope

In:

- deck.md parser and canonical printer, with the reading rules.
- Cell dialect validation and rendering.
- Core ops, effects, layout folding, history, and all laws passing.
- Server: init, serve, WebSocket protocol, atomic debounced writes, watching,
  external edit handling with rebase.
- Client: two panes with draggable divider and hiding, modal keymap, cells
  pane, canvas with grid placement, drag, resize, keyboard nudging, variants,
  alignment, overflow flags, status line.

Out (later):

- Presenting mode and export (static HTML, PDF via print CSS).
- A separate title area in the theme.
- Groups of cells.
- Free-form CSS per cell, shrink-to-fit text.
- Other aspect ratios.
- Undo history persisted across restarts.
- Tables, math, footnotes in the dialect.
- State patches instead of full-state broadcast.
- A TUI client.

## M0: spikes

Each spike is small (about half a day), answers one question, and ends with a
short note in `docs/spikes/Sn-name.md`: what was tried, what works, what to
use.

| Spike | Question | Done when |
|---|---|---|
| S1 drag | Can Lustre handle pointer down, move, up (and pointer capture) to drag and resize a box snapping to a 32x18 grid, smoothly, without handwritten JS? | A box drags and resizes on a scaled 16:9 grid in Chromium and Safari |
| S2 measure | Can the client measure a rendered element (overflow detection) and make text areas grow with content without handwritten JS? Check CSS `field-sizing: content` support | Overflow of a box is detected; a text area grows |
| S3 socket | mist WebSocket round trip with a codec shared from a core package | A message type defined in core goes both ways |
| S4 files | polly on macOS (replaced by a content poller, P18); suppressing events from our own writes by hash; atomic write via temp file and rename | An external edit is seen within 300 ms; own writes are ignored; no partial file is ever observed |
| S5 jot | Does `jot` run on the JavaScript target, cover the allowed constructs, and expose enough structure to reject forbidden ones? | Decision: use jot as is, wrap it, or write a small parser for the subset |

If a spike shows that a browser capability needs JavaScript, stop and report
the options before continuing (see CLAUDE.md).

## M1: core

Types, IdSupply, parser and printer, `normalize_edit`, `apply` for every op,
`fold_effects`, layout ops, history with coalescing, codecs. Create
`examples/talk/` here, starting from the example in 02-file-format.md, with a
few more slides that exercise every allowed construct and every marker form.

Done when: every law in 03-data-model.md passes on both targets, and the
printer reproduces `examples/talk/deck.md` byte for byte.

## M2: server

`zeno init`, `zeno serve`, state owner, protocol, writes, watching, rebase,
view state, static serving.

Done when the integration scenarios below pass.

### External edit scenarios

1. Edit a cell's text in an outside editor: same ID, layout kept.
2. Add a paragraph with no marker after a slide marker: new cell, flows.
3. Add a bare `---` line: new slide with a fresh ID; markers added on save.
4. Delete a cell: its record moves to orphans.
5. Cut a cell, save, paste it elsewhere, save: ID revived, layout restored.
6. Copy a cell including its marker: the copy gets a fresh ID.
7. Introduce a parse error: Zeno keeps state, shows the line, does not write;
   fixing the error resumes normally.
8. Edit while a Zeno write is pending: pending ops are rebased; ops on removed
   cells are dropped with a notice.
9. Corrupt layout.json: Zeno keeps its layout and reports it.
10. Kill the server between the deck.md and layout.json writes: on restart
    the consistency step repairs the layout.

## M3: client, cells pane

Panes and divider, hiding, command and edit modes, all command-mode keys,
`normalize_edit` problems shown, kind cycling, clipboard, undo and redo,
status line.

## M4: client, canvas

Rendering slides from deck, layout and theme; placement; drag and resize;
canvas keys; variants and alignment; overflow flags; theme reload.

## M5: hardening

Use Zeno to make a real talk. Fix what hurts. Update these docs where the
implementation taught something.
