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
    `/zeno/zeno.css`, `/theme.css` and `/zeno/zeno_client.js` (since M5 under `/.zeno/`).
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

- M5 hardening, first pass (2026-10-27), each fix its own revision:
  - `X` in command mode purges orphans (the user's choice), one undo step,
    with a notice; browser check.
  - Updates on large decks: a profile of typing in a 60-slide deck showed
    every slide's probes rendering again with each state, because a memo
    around the probe layer dropped the inner memos' cache. Probes are now
    memoised per slide on a string key, `id.parse` checks bytes, and slide
    numbers are padded by byte size. Script time for ten typed characters
    with a state after each: 401 to 113 ms at 60 slides, 622 to 212 ms at
    150. Typing right after `o` lands in the new cell even at 150 slides.
  - Theme reload keeps the old stylesheet until the new one has loaded (no
    unstyled flash); browser check that the old link goes.
  - A released drag keeps its preview until a state shows the cell at the
    dropped area (or its `Place` is rejected, the cell is gone, or a second
    passes). Not covered by a browser check: the race needs a state from
    another edit between release and echo.
  - Editor paths moved to `/.zeno/...` and `/.zeno/ws`; deck files never
    start with a dot, so a deck's own `zeno/` folder or `ws` file is served.
  - `zeno serve` on a taken port prints one plain line and exits 1 instead
    of a supervisor report and an Erlang exit; the URL is printed once.
  - Looked at and fine: writing a talk from `zeno init` with cells, notes,
    breaks, lists and code; canvas placing, variants and alignment;
    overflow on a long cell; start with a broken layout.json or no
    theme.css; CLI usage and error messages.
  - Tests: core 47 on both targets, server 26, client 26, e2e 21.

## Todo

- M5, with the user: use Zeno on a real talk and collect what hurts.
- `Ctrl-[` and `Ctrl-]` on a Mac keyboard (only checked in headless
  Chrome). On layouts where `[` needs Option they cannot be typed; matching
  `code` `BracketLeft` as well would be the fix, if the user wants it.
- Safari: the user said not now (2026-10-27); D18 stays as it is.
- Possibly report the jot `{=mark=}` bug upstream (ask the user first; it is
  outward-facing).

## Next step

M5 continues with the user's own use. Nothing is half done; every fix of the
first pass is committed with its test and docs.

1. Ask the user how a real talk went in Zeno (`cp -r examples/talk
   <somewhere>` or `just zeno init <folder>`, then `just zeno serve
   <folder>`, open http://127.0.0.1:4870/ in Chrome; never serve
   `examples/talk` in place). Fix what they report, each fix with a test
   and the doc it changes, in its own revision.
2. Points to raise with them:
   - Placing a one-line cell gives a one-row box, so a larger variant
     overflows at once (flagged, by design: nothing resizes itself). They
     may want `Enter` or `v` to grow the box to fit, which would change
     04-layout.md (ask first).
   - `Ctrl-[` on their keyboard (see Todo).
   - The jot report.

Known rough edges left:

- A pointer released outside the window: the drag ends when the pointer
  leaves the slide pane, so it commits the last snapped area.
- No `Tab` cycling inside the slide pane beyond `j`/`k`; no multi-select.
- The cells pane re-renders every cell on each state (about 10 ms at 60
  slides after the first pass). Memoising rows would need a key of
  selection, mode, draft, diagnostics and overflow per cell.

Tests to keep: `just test` (core, server, client, e2e, about 20 s). Add a
browser check for each fix that changes behaviour, and record settled
behaviour in the docs in the same change.

Things learned so far:

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
- Lustre 5.7: never wrap one `element.memo` in another; a kept outer memo
  loses the inner memos' cache and they all render again next time. Memo
  dependencies compare by reference, except strings and numbers, so build
  a string key from decoded values.
- Grapheme functions are slow on JavaScript (Intl.Segmenter); use byte
  sizes and bit arrays where the text is ASCII.
- Profiling the client: CDP `Profiler.start`/`stop` and
  `Performance.getMetrics` on an unminified bundle (drop `--minify` from
  `just client` for the run); the scratch test is not kept in the repo.
- `mist.start` on a taken port logs a supervisor report and exits the
  linked caller; trap exits and quiet `logging` around it.
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
- 2026-10-27: M5 first pass: `X` purges orphans, faster updates on large
  decks, theme reload without a flash, steadier drag preview, editor paths
  under `/.zeno/`, plain CLI error for a taken port.
