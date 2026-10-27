# Roadmap progress

Progress tracker. The design roadmap is docs/08-roadmap.md.

## Done

- Toolchain: gleam 1.19.2, Erlang/OTP 29, rebar3 3.28.0 (Homebrew), node 26.
  Chrome for Testing 156 headless shell in `~/Library/Caches/zeno-cft/156/`
  for browser checks.
- M0, all five spikes, each with a note in `docs/spikes/`:
  - S1 drag: pure Lustre and CSS (hit-cell overlay, grab from `offsetX`).
    Works in Chromium.
  - S2 measure: CSS scroll-state probes report overflow and rendered height
    to the model via `animationstart`; mirror text areas grow. Chromium only
    so far.
  - S3 socket: shared gleam_json codec on both targets, mist server,
    lustre_websocket client. Round trip verified from Erlang and in Chrome.
  - S4 files: atomic writes (temp file, fsync FFI, rename) verified; polly
    misses same-second edits, and a content-hash poller does not.
  - S5 jot: jot 12.x covers the dialect; wrap it with an AST walker; own line
    splitter for reading rule 5.
- docs/07-stack.md package statuses updated.

## Todo

- Decisions waiting for the user (see Next step).
- M1 core, M2 server, M3 and M4 client, M5 hardening.

## Next step

1. Get the user's answers on the open decisions from M0:
   - P18: replace polly with the content-hash poller (`spikes/s4_files/src/store.gleam`,
     `poll`). Recommended. If yes, update P18 in docs/09-decisions.md,
     06-runtime.md (watching) and 07-stack.md.
   - Client WebSocket: `lustre_websocket` (third-party Gleam package with
     its own small JS FFI). Recommended. Alternatives are in
     docs/spikes/S3-socket.md.
   - Safari: whether to verify S1 and S2 in Safari before M4, and which
     overflow fallback to use if Safari lacks scroll-state queries
     (docs/spikes/S2-measure.md).
   - Dialect: whether djot extras (super and subscript, insert, delete,
     mark, symbols) are forbidden, as proposed in docs/spikes/S5-jot.md. If
     yes, add them to the forbidden list in 02-file-format.md.
2. Start M1 in `core/` as laid out in docs/07-stack.md (gleam package,
   target-agnostic, deps gleam_json, jot 12.x, gleam_time for Timestamp,
   dev deps gleeunit and qcheck). Order inside M1:
   `id.gleam` (opaque `Id(tag)`, own UUID parser, `IdSupply`), then
   `deck.gleam` and the invariants, `file.gleam` (parser with the reading
   rules, using the splitter from `spikes/s5_jot/src/blocks.gleam`, and the
   canonical printer), `op.gleam` (`apply`, `normalize_edit`), `layout.gleam`
   (`fold_effects`, layout ops, layout.json codec), `history.gleam`,
   `protocol.gleam`. Write `examples/talk/` (canonical, byte-for-byte
   round trip) plus a hand-written fixture for ID-less markers, preamble
   and duplicates. Laws as qcheck properties on both targets.
3. Things learned in M0 to carry into M1 to M4:
   - Lustre renders on the next animation frame; `html.textarea` is always
     controlled (pass the model text back in).
   - Never use `jot.to_html`; render the AST to Lustre elements and sanitise
     URLs.
   - Synthetic browser input over CDP must be paced by one frame (20 ms).

Commands: `just --list`; `just spikes-test` runs every spike check (about 2
minutes, it starts headless Chrome itself).

## Log

- 2026-10-27: toolchain installed, scaffolding, all M0 spikes done with
  notes; decisions listed under Next step are open.
