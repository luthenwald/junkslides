# Roadmap progress

Progress tracker. The design roadmap is docs/08-roadmap.md.

## Done

- Toolchain: gleam 1.19.2, Erlang/OTP 29, rebar3 3.28.0 (Homebrew), node 26.
  Chrome for Testing 156 headless shell in `~/Library/Caches/zeno-cft/156/`
  for browser checks.
- M0, all five spikes, each with a note in `docs/spikes/`:
  - S1 drag: pure Lustre and CSS (hit-cell overlay, grab from `offsetX`).
  - S2 measure: CSS scroll-state probes report overflow and rendered height
    to the model via `animationstart`; mirror text areas grow.
  - S3 socket: shared gleam_json codec, mist server, lustre_websocket client.
  - S4 files: atomic writes (temp file, fsync FFI, rename); content-hash
    poller instead of polly.
  - S5 jot: jot 12.x wrapped with an AST walker; own block splitter.
- M0 decisions (2026-10-27), recorded in docs/09-decisions.md:
  - P18 changed: own content-hash poller instead of polly.
  - D17: `lustre_websocket` for the client socket.
  - D18: the prototype targets Chromium; Safari revisited in M5.
  - djot extras (super and subscript, insert, delete, mark, symbols) are
    forbidden (02-file-format.md).
- M1 core, in `core/` (package `zeno_core`), done:
  - Modules: id, line, deck, op, layout, history, dialect, blocks, file,
    codec, protocol. See docs/07-stack.md for what each holds.
  - `examples/talk/` (deck.md, layout.json, theme.css) round-trips byte for
    byte; `core/test/fixtures/hand.md` covers ID-less markers, preamble,
    bare breaks, unmarked blocks and duplicate IDs.
  - All ten laws of docs/03-data-model.md pass as qcheck properties on both
    targets (`core/test/laws_test.gleam`), plus unit tests per op, the parser
    and printer, layout, history, dialect and protocol: 47 tests.
  - The properties were checked by mutation: breaking effects, IDs, blank
    edges, retire, revive, placement checks, history, normalisation, the
    printer or the paste rule each makes them fail.
  - Found by the properties: `Split` could cut ` ---` into a line that is
    exactly `---`. Split now refuses cuts that leave a structural line
    (03-data-model.md, Errors).

- M2 server, in `server/` (package `zeno_server`), done:
  - Modules: `zeno_server` (CLI), `state` (owner actor), `store`, `web`,
    `theme`, `view`, plus `zeno_server_store_ffi.erl` (write and fsync).
  - All ten external edit scenarios of docs/08-roadmap.md pass with a client
    connected over the WebSocket (`server/test/scenarios_test.gleam`), plus
    one where the write is due before polling sees the edit. Other tests:
    rejection, undo and redo, view state, theme reload, static files and path
    checks, `zeno init`, atomic writes: 25 tests, about 5 s.
  - Checked by mutation: skipping the read before a write, replaying with a
    new supply, skipping the consistency step after a rebase, the dropped
    notice, the rebase itself, writing while broken (both files), the
    consistency step on start, recording the own-write hash, telling late
    clients about problems, and the theme reload each make a test fail.
    Comparing an outside edit with the current deck instead of the saved one
    gives the same result, since the consistency step repairs it.
  - Design details settled by the implementation are in docs/06-runtime.md
    (rebase by groups with their supply, a read before every write, no
    writes while a file has a problem, the path table) and docs/07-stack.md.

- M3 client, cells pane, in `client/` (package `zeno_client`), done:
  - Modules: `zeno_client` (main), `app` (model, update, socket),
    `ui` (screen), and the pure `nav`, `keymap` and `edit`. Styles in
    `client/assets/zeno.css`. `just client` bundles both into
    `server/priv/static` (not in version control); the page at `/` loads
    `/zeno/zeno.css`, `/theme.css` and `/zeno/zeno_client.js`.
  - Panes with a draggable divider (S1 hit strips) and hiding, saved with
    `SaveView`; command and edit modes with every command-mode key of
    05-editor.md; typing sent after a 200 ms pause, `---` only on commit;
    marker-line problems and dialect diagnostics under the cell; kind
    cycling, cut, copy and paste (IDs revive), duplicate, merge, breaks,
    split at the cursor (`Alt-Enter`), undo and redo; status line with mode,
    slide number, problem and orphan counts, connection and notices;
    reconnecting after a second.
  - Focus without JavaScript: the element that should have focus carries
    `autofocus` with a counter value, and Lustre calls `focus()` whenever it
    is added or changes (docs/07-stack.md, Client techniques).
  - Tests: 16 unit tests of the pure modules on JavaScript, and 14 browser
    checks in `e2e/` (package `zeno_e2e`): headless Chrome against an
    in-process server on a copy of `examples/talk`, checked through the DOM
    and the files on disk, including an edit kept across a lost connection.
    About 6 s.
  - Checked by mutation: typing that sends breaks, a commit that ignores a
    marker line, cut selecting the wrong neighbour, no focus on the
    selection, both panes hideable, new cells not followed, move up staying
    in its slide, and a split ignoring dropped blank lines each make a test
    fail.
  - Found on the way: a view.json with both panes hidden left nothing to
    focus; the client now shows the cells pane then. Committing while
    offline would have dropped the draft; it now stays in its cell.
  - Behaviour settled by the implementation is in docs/05-editor.md (empty
    slide rows, clicking into text, cursor at the end, Esc twice to drop,
    the editor's own clipboard, connection).

- M4 client, slide pane (canvas), in `client/`, done:
  - New modules: `slide` (slides drawn from the jot AST per the theme
    contract, the editor layer, overflow probes) and the pure `canvas`
    (areas from drawn boxes, moves, resizes, nudges, variant and alignment
    cycles, drawn-cell navigation). `app` gained the `Canvas` mode, drags,
    probe reports and the theme counter; `keymap` the canvas keys and `Tab`.
  - The theme is linked from the Lustre view as `/theme.css?v=N`, and
    `ReloadTheme` bumps `N`; the server page no longer links it.
  - Canvas mode: `Tab` or `Esc` in and out, every key of 05-editor.md;
    pressing a drawn cell selects it and enters canvas mode; drag to move
    (placing an unplaced cell with its rendered size), handle to resize,
    one `Place` per drag with a snapped preview; nudges and resizes of an
    unplaced cell place it first; edge-stopped keys send nothing.
  - Rendered sizes come from the event target's layout offsets, decoded
    like any field, instead of the rows probe of S2. Overflow: one hidden
    probe per drawn cell for the whole deck (prefix copies of the body for
    flowing cells), dashed outline, quiet mark in the cells pane, count in
    the status line.
  - Base slide styles (grid, body area, links, alignment) in zeno.css at
    zero specificity, so the theme always wins.
  - Tests: 25 client unit tests; 20 browser checks (6 new in
    `e2e/test/canvas_test.gleam`: drawing, canvas keys on layout.json,
    drag with preview and handle resize, dragging out of the flow, overflow,
    theme reload). The e2e helpers moved to `e2e/src/harness.gleam`.
  - Checked by mutation: no scroll-state query, a click that sends `Place`,
    an ignored `ReloadTheme`, canvas keys without the drawn box, and the
    preview on the wrong cell each make a test fail. Auto-placed drag
    targets no longer fail anything, since the handle is hidden while
    dragging; the explicit placement stays as a safeguard.
  - Found on the way: drag targets auto-placed in the layer grid flowed
    around the resize handle and missed their cells.
  - Settled behaviour is in docs/05-editor.md (Canvas mode) and
    docs/04-layout.md (overflow of flowing cells, base styles, reload).

## Todo

- M5 hardening (docs/08-roadmap.md): make a real talk with Zeno, fix what
  hurts.
- Ask the user: a key or status-line action for `PurgeOrphans` (05-editor.md
  has none).
- Possibly report the jot `{=mark=}` bug upstream (ask the user first; it is
  outward-facing).

## Next step

M5, hardening. Read docs/08-roadmap.md (M5), docs/05-editor.md and
docs/04-layout.md, then use the editor on a real deck: `cp -r examples/talk
<somewhere>` (never serve `examples/talk` in place) and `just zeno serve
<somewhere>`, open http://127.0.0.1:4870/ in Chrome.

Open points to settle with the user first:

1. `PurgeOrphans` has no key. Options to put to them: a command-mode key
   (for example `X`, with a notice saying how many records went), or only a
   CLI command (`zeno purge <folder>`). Do not pick one silently.
2. Safari (D18 says revisit in M5): typed arithmetic in the fit, scroll-state
   probes (no overflow flags without them, S2 fallback 1) and
   `field-sizing` are the features to check.
3. The jot `{=mark=}` report upstream.

Known rough edges to look at while using it:

- `Ctrl-[` and `Ctrl-]` were only checked in headless Chrome; try them on a
  Mac keyboard.
- The theme is linked from the view, so the first paint has no theme for a
  frame.
- A state that arrives between a drag's release and its own echo ends the
  preview early; the cell may jump back for a frame.
- A pointer released outside the window: the drag ends when the pointer
  leaves the slide pane, so it commits the last snapped area.
- Image paths starting with `zeno/` or `ws` would hit the editor's own
  routes (06-runtime.md, Serving).
- Overflow probes copy every slide; with a large deck, check typing latency
  (they are memoised on the state, so only a new state re-renders them).
- No `Tab` cycling inside the slide pane beyond `j`/`k`; no multi-select.

Tests to keep: `just test` (core, server, client, e2e, about 20 s). Add a
browser check for each fix that changes behaviour, and record settled
behaviour in the docs in the same change.

Things learned so far to carry into M4 and M5:

- `core` API notes: `op.normalize_edit(deck, cell, text)` takes the deck;
  `op.apply_all` is all-or-nothing; `layout.apply(layout, deck, op)`;
  `layout.record(layout, cell)` gives a cell's record with defaults;
  `history.record_edit` coalesces typing per cell within a second of the
  step's first edit; `file.parse` returns the new `IdSupply`.
- Lustre renders on the next animation frame; `html.textarea` is always
  controlled (pass the model text back in). Lustre's `autofocus` hook runs
  on every add or value change of the attribute; that is how focus moves.
- Chrome puts the cursor at the end of a text area's text on `focus()`.
- Never use `jot.to_html`; render the AST (`dialect.parse`) to Lustre
  elements and pass URLs through `dialect.safe_url`.
- Synthetic browser input over CDP must be paced by one frame (20 ms).
- An event's `target` decodes like any field: `offsetLeft`, `offsetWidth`
  and friends give layout sizes in unscaled pixels, `selectionStart` the
  cursor. That covers measurement without JavaScript of our own.
- Grid auto-placement flows around explicitly placed items; place generated
  items explicitly. Lustre writes inline styles as `grid-area:4 / 5 / ...`
  (no space after the colon), which matters to tests reading `style`.
- Option changes `key` on macOS (Option-l is `¬`); match Alt keys on
  `code`. `cdp.key` sends `code` for single letters.
  `cdp.key` types the key's text unless the page prevents it.
- After restoring a mutated file with an older mtime, gleam may reuse the
  stale build; `touch` the file. Test runs that are interrupted can leave
  files in `build/` (scenario folders, view files); the e2e helper deletes
  the view file of its folder.
- `.gitignore` patterns with an inner slash are anchored at the root.
- Server API notes: `state.start(state.Config(folder, view_file, poll,
  debounce))` returns the owner's subject; `web.start(web.Config(port,
  folder, client), owner)`; clients join with a `Subject(ServerMsg)` and are
  greeted with the state (the client does not send `Hello`).
  `server/test/support/harness.gleam` serves a copy of `examples/talk` with
  a stratus client; `e2e/test/editor_test.gleam` does the same with Chrome.
- Rebasing replays each `Apply` group with the `IdSupply` it used, so IDs
  made by unsaved ops survive an outside edit. An unsaved undo or redo
  cannot be replayed and is dropped with a notice.
- New cells are named by the server; the client follows them by looking for
  a cell ID that was not in the previous state (`app.Follow`).
- Canvas API notes: `canvas.area_of_box` rounds a drawn box up to units and
  pushes it inside the grid; `slide.box_decoder` reads a drawn cell's box
  from an event target; `app.overflowing` gives the flagged content cells.

Commands: `just --list`; `just test` runs everything that is not a spike:
core on both targets, server, client unit tests and the browser checks
(about 20 s, it starts headless Chrome itself); `just client` builds the
bundle; `just zeno init <folder>` and `just zeno serve <folder>` build the
client and run the command from the current folder; `just spikes-test` runs
every spike check (about 2 minutes).

## Log

- 2026-10-27: toolchain installed, scaffolding, all M0 spikes done with
  notes.
- 2026-10-27: M0 decisions made with the user and recorded; M1 core done,
  all laws passing on both targets.
- 2026-10-27: M2 server done, all ten external edit scenarios passing.
- 2026-10-27: M3 cells pane done, unit and browser checks passing.
- 2026-10-27: M4 slide pane done: canvas mode, drag and resize, overflow
  flags, theme reload; unit and browser checks passing.
