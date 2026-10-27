# 07/10 Stack

## Language

Gleam, for everything:

- the server on the Erlang target (BEAM);
- the client on the JavaScript target, with Lustre;
- a shared `core` package that compiles to both.

No handwritten JavaScript or TypeScript. Small Erlang FFI on the server is
acceptable when a Gleam library is missing, kept in one module and documented.
If a browser capability is unreachable from Gleam libraries, stop and decide
explicitly (see CLAUDE.md) rather than adding JavaScript FFI quietly.

Why Gleam: typed (opaque types, phantom types, exhaustive matching), one
language and one set of types on both sides, fast compilation, and Lustre's
Elm architecture matches the design closely: the update messages are
essentially the `Op` type.

Known limits, accepted: no GADTs or type classes, so some guarantees are laws
instead of types; JSON codecs are written by hand.

## Packages

| Package | Used for | Where | Status |
|---|---|---|---|
| `lustre` | Client UI (Elm architecture) | client | chosen; 5.7.1 in the spikes |
| `lustre_dev_tools` | Building and bundling the client | client (dev) | chosen; 2.4.0 bundles with Bun into `dist/` |
| `mist` | HTTP server and WebSocket | server | chosen; round trip verified in S3 |
| `lustre_websocket` | WebSocket from the Lustre client | client | chosen (D17); ships its own small JS FFI. No reconnect logic, the client calls `init` again on close |
| `gleam_json` | Codecs for protocol, layout.json, view state | core | chosen |
| `youid` | UUIDv7 generation (`uuid.v7()`) and parsing | server, core | chosen |
| `simplifile` | File reading and writing | server | chosen; `rename` is `file:rename/2` and atomic for readers (S4). No fsync: a one-function Erlang FFI calls `file:sync/1` |
| `gleam_crypto` | sha256 of written and watched files | server | chosen (S4) |
| `jot` | Parsing djot cell bodies | core | chosen (S5): 12.x, covers the dialect on both targets; used through a wrapper that walks the AST for diagnostics. Rendering goes from the AST to Lustre elements, never through `to_html` |
| `gleeunit` | Test runner | all | chosen |
| `qcheck` | Property tests with shrinking | core | chosen |
| `stratus` | WebSocket client for server tests and the CDP driver | server (dev) | chosen (S3) |

Browser capabilities: drag, resize, overflow detection and rendered size
work with Lustre events and CSS only in Chromium (spikes S1 and S2). No
pointer capture or measurement binding is needed there. The prototype
targets Chromium (D18).

File watching is our own content-hash poller in the server (P18), not
`polly`, which misses a second edit within the same second (S4).

## Project layout

```
zeno/
  README.md
  CLAUDE.md
  docs/
  core/        target-agnostic package
    src/zeno/
      id.gleam          Id, tags, IdSupply
      deck.gleam        Kind, Cell, Slide, Deck, Position, invariants
      op.gleam          Op, Effect, apply, normalize_edit, OpError
      layout.gleam      Area, CellRecord, Layout, LayoutOp, fold_effects
      history.gleam     snapshots, undo, redo, coalescing
      dialect.gleam     cell body validation and rendering (via jot)
      file.gleam        deck.md parse and print, layout.json codecs
      protocol.gleam    client/server messages and codecs
    test/
  server/      Erlang target
    src/zeno/
      server.gleam      CLI entry: init, serve
      state.gleam       owner process: state, history, rebase
      store.gleam       atomic writes, hashing
      watch.gleam       file watching
      web.gleam         HTTP, WebSocket, static files
  client/      JavaScript target
    src/zeno/
      app.gleam         Lustre application, model, update
      cells.gleam       cells pane
      canvas.gleam      slide pane, drag and resize
      keys.gleam        keymap
  examples/
    talk/        a sample deck used in development and integration tests
```

`server` and `client` depend on `core` by path. The module list is a
suggestion; the package boundaries are not.

## Toolchain

```
brew install gleam erlang rebar3
```

Use current stable versions. Record exact versions in each `gleam.toml` and in
the lock files.

## Testing

- `core`: unit tests for the parser, printer and each op; property tests for
  the laws in 03-data-model.md. Run with `gleam test` in `core/`, on both
  targets (`--target erlang` and `--target javascript`), since core runs on
  both.
- `server`: integration tests on a temporary copy of `examples/talk`, covering
  the external edit scenarios in 08-roadmap.md.
- `client`: kept thin; logic that can live in `core` should.
- Browser checks: Chrome for Testing (headless shell, kept outside the repo
  in `~/Library/Caches/zeno-cft/`) is driven over the DevTools protocol from
  Gleam, using only the DOM, Input, Page and Emulation domains. See
  `spikes/browser` and `just browser-test`. Synthetic input is paced by one
  frame. Safari is not covered.
