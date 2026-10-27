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

## Todo

- M2 server, M3 and M4 client, M5 hardening.
- Possibly report the jot `{=mark=}` bug upstream (ask the user first; it is
  outward-facing).

## Next step

M2, the server, in a new `server/` package (Erlang target, `zeno_server`),
depending on `core` by path (`zeno_core = { path = "../core" }`). Read
docs/06-runtime.md and the external edit scenarios in docs/08-roadmap.md.

Suggested order:

1. `store.gleam`: `write_atomic` (temp file `.name.zeno-tmp` in the same
   folder, `file:sync` through a one-function Erlang FFI, then
   `simplifile.rename`), sha256 with gleam_crypto. Port from
   `spikes/s4_files/src/store.gleam` and `s4_store_ffi.erl`.
2. `watch.gleam`: the content-hash poller (250 ms) from the S4 spike, with
   own-write suppression by hash (P18).
3. `state.gleam`: the owner process (an actor). Holds deck, layout, history,
   the last written hashes, pending ops since the last deck.md write, the
   variants and the view. Seeds `id.supply(now_ms, crypto.strong_random_bytes(8))`
   on start and reseeds per change (the supply skips live IDs either way).
   Applies `Apply` with `op.apply_all`, then `layout.fold_effects`, then
   `history.record` (or `history.record_edit` when the ops are one
   `EditText`). Layout ops via `layout.apply`. External deck.md edits:
   `file.parse`, `layout.apply_external`, rebase pending ops (drop the ones
   that fail, send a `Notice`), record a step, write. On a parse error keep
   state, send `Notice` with the line, do not write.
   Debounced writes (300 ms): deck.md first, then layout.json, skipping
   unchanged bytes. On load, run `layout.consistency`.
4. `web.gleam`: mist on 127.0.0.1:4870; `/ws` speaks `protocol` (full
   `State` broadcast after each change, `protocol.diagnostics(deck)`);
   static files for the client bundle, theme.css and deck assets, with paths
   kept inside the deck folder.
5. `server.gleam`: CLI `zeno init <folder>` (minimal deck plus default
   theme, copy from `examples/talk/theme.css`) and `zeno serve <folder>`.
   Theme variants from `--zeno-variants` in theme.css; `ReloadTheme` on
   change. View state in `~/.config/zeno/view.json` keyed by deck path (P15).
6. Integration tests: the ten external edit scenarios of docs/08-roadmap.md
   on a temp copy of `examples/talk`, using stratus as the WebSocket client
   (as in `spikes/s3_socket/server/test`).

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

Commands: `just --list`; `just test` runs the core tests on both targets
(seconds); `just spikes-test` runs every spike check (about 2 minutes, it
starts headless Chrome itself).

## Log

- 2026-10-27: toolchain installed, scaffolding, all M0 spikes done with
  notes.
- 2026-10-27: M0 decisions made with the user and recorded; M1 core done,
  all laws passing on both targets.
