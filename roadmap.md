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

## Todo

- M4 client canvas, M5 hardening.
- Possibly report the jot `{=mark=}` bug upstream (ask the user first; it is
  outward-facing).

## Next step

M4, the slide pane (canvas), in `client/`. Read docs/04-layout.md (all of
it, including the theme contract), docs/05-editor.md (Canvas mode, Visual
style), the S1 and S2 spike notes, and `client/src/zeno_client/ui.gleam`
(the placeholder `slide_pane`) first.

Suggested order:

1. Rendering: a new module (for example `zeno_client/slide.gleam`) that
   draws the slide of the selection from deck, layout and theme. Structure
   per the theme contract: `.zeno-slide` (1920x1080, a 32x18 grid of 60 px
   units) scaled into the pane with the S1 CSS (`container-type: size` on
   the stage, `scale: min(100cqw / 1920px, 100cqh / 1080px)`, centred with
   `translate`); `.zeno-body` holding the unplaced content cells in source
   order; placed cells as `.zeno-cell[data-placed]` with an inline
   `grid-area`; `data-variant` and `data-align` from the cell record. Notes
   cells are not drawn. Cell bodies go from `dialect.parse` (jot AST) to
   Lustre elements, never `jot.to_html`; image and link URLs through
   `dialect.safe_url`, images resolved against the deck folder (the server
   serves it at `/`). Keep the editor's `ze-` classes off the slide.
2. Theme reload: render the theme `<link>` inside the Lustre view with a
   counter in its URL (`/theme.css?v=N`), bump it on `ReloadTheme`, and
   drop the static theme link from the page in `server/src/zeno_server/
   web.gleam` (and the path table in docs/06-runtime.md).
3. Selection and modes: clicking a drawn cell selects it (both panes);
   `Tab` toggles between command mode and a new canvas mode (add `Canvas` to
   `app.Mode` and a canvas keymap to `keymap.gleam`); canvas keys from
   05-editor.md: `j`/`k` through drawn cells of the slide, `Enter` places an
   unplaced cell where it is drawn, Alt-hjkl or arrows nudge, HJKL or
   Shift-arrows resize, `f` unplaces, `v` cycles variants (none, then each
   name of `State.variants`), `a` cycles alignment, `u`/`U`. Layout ops go
   through `ApplyLayout(seq, op)`; reuse `app.apply`'s seq numbering.
4. Drag and resize (S1 approach A): pointerdown on a drawn cell or its
   handle, `offsetX`/`offsetY` divided by 60 for the grab cell, an overlay
   of 32x18 hit cells reporting `pointerenter`, clamped to the grid, one
   `Place` on pointerup or pointercancel (also treat `pointerleave` on the
   stage as a cancel). Children of a cell need `pointer-events: none`.
   Placing an unplaced cell needs its rendered height in grid units: the S2
   rows probe (18 probes, smallest that fits), rendered only for the
   dragged cell.
5. Overflow (S2): a hidden scroll-state probe behind each drawn box
   reporting `fits`/`overflows` through `animationstart`; keep a set of
   overflowing cells in the model; dashed outline on the canvas, a quiet
   mark in the cells pane (`ui.problems`), and a count in the status line.
6. `PurgeOrphans` has no key yet; propose one (or a status-line action) to
   the user rather than inventing it silently.
7. Tests: canvas logic that is pure (cycling variants and alignment, nudge
   and resize clamping, the drag arithmetic) as client unit tests; browser
   checks in `e2e/test/` reusing `open`, `press` and `key`, plus
   `cdp.mouse` and `cdp.box` for drags (pace by one frame) and
   `cdp.screenshot` to look at the slide while working.

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

Commands: `just --list`; `just test` runs everything that is not a spike:
core on both targets, server, client unit tests and the browser checks
(about 15 s, it starts headless Chrome itself); `just client` builds the
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
