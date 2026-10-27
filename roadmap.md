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

## Todo

- M3 and M4 client, M5 hardening.
- Possibly report the jot `{=mark=}` bug upstream (ask the user first; it is
  outward-facing).

## Next step

M3, the client's cells pane, in a new `client/` package (JavaScript target,
`zeno_client`, Lustre 5.x and `lustre_websocket`, D17), depending on `core`
by path. Read docs/05-editor.md (Screen, Cells pane, Modes, Keymap, Undo,
View state, Visual style) and the S1 to S3 spike notes first.

Suggested order:

1. Package and build: `lustre_dev_tools` bundles the client; put the output
   where the server serves it, `server/priv/static/client.js` (the page at
   `/` loads `/zeno/client.js` and `/theme.css`; see the path table in
   docs/06-runtime.md, Serving). Add a `just client` recipe that builds the
   bundle, and let `just zeno serve` use it. Check whether
   `lustre/dev build` can name its output `client.js` directly or needs a
   copy step in the recipe.
2. Socket and model: connect to `/ws` (reconnect by calling `init` again on
   close, as in S3), send `Hello`, keep `State` as the model's copy of
   deck, layout, diagnostics, variants and view. Number `Apply` and
   `ApplyLayout` with `seq`, show `Rejected` and `Notice` in the status line.
   The server broadcasts the full `State` after every change and answers a
   no-op undo with `State` too.
3. Panes: cells pane and slide pane with a draggable divider and hiding
   (S1 drag approach for the divider), `SaveView` on change; the slide pane
   can stay a placeholder until M4.
4. Cells pane: one controlled `html.textarea` per cell, growing with the
   mirror technique from S2. Command and edit modes and the full command-mode
   keymap of 05-editor.md. Typing sends `op.normalize_edit(deck, cell,
   text)` as one `Apply` per change (the server coalesces typing into one
   undo step per cell within a second); show `EditProblem`s inline.
   Diagnostics from `State` mark cells. Kind cycling, clipboard (cut, copy,
   paste through `Paste` so IDs revive), undo and redo, status line.
5. Tests: logic that can live in `core` should; browser checks through the
   CDP driver in `spikes/browser` (Chromium only, D18), paced by one frame.

Things learned so far to carry into M2 to M4:

- `core` API notes: `op.normalize_edit(deck, cell, text)` takes the deck;
  `op.apply_all` is all-or-nothing; `layout.apply(layout, deck, op)`;
  `history.record_edit` coalesces typing per cell within a second of the
  step's first edit; `file.parse` returns the new `IdSupply`.
- Lustre renders on the next animation frame; `html.textarea` is always
  controlled (pass the model text back in).
- Never use `jot.to_html`; render the AST (`dialect.parse`) to Lustre
  elements and pass URLs through `dialect.safe_url`.
- Synthetic browser input over CDP must be paced by one frame (20 ms).
- After restoring a mutated file with an older mtime, gleam may reuse the
  stale build; `touch` the file.

- Server API notes: `state.start(state.Config(folder, view_file, poll,
  debounce))` returns the owner's subject; `web.start(web.Config(port,
  folder, client), owner)`; clients join with a `Subject(ServerMsg)`.
  `support/harness.gleam` in the server tests serves a copy of
  `examples/talk` and connects a stratus client; reuse it for any new
  server behaviour.
- Rebasing replays each `Apply` group with the `IdSupply` it used, so IDs
  made by unsaved ops survive an outside edit. An unsaved undo or redo
  cannot be replayed and is dropped with a notice.

Commands: `just --list`; `just test` runs the core tests on both targets and
the server tests (about 15 s); `just zeno init <folder>` and
`just zeno serve <folder>` run the command from the current folder;
`just spikes-test` runs every spike check (about 2 minutes, it starts
headless Chrome itself).

## Log

- 2026-10-27: toolchain installed, scaffolding, all M0 spikes done with
  notes.
- 2026-10-27: M0 decisions made with the user and recorded; M1 core done,
  all laws passing on both targets.
- 2026-10-27: M2 server done, all ten external edit scenarios passing.
