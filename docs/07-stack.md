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
| `lustre` | Client UI (Elm architecture) | client | chosen |
| `lustre_dev_tools` | Building and bundling the client | client (dev) | chosen |
| `mist` | HTTP server and WebSocket | server | chosen |
| `gleam_json` | Codecs for protocol, layout.json, view state | core | chosen |
| `youid` | UUIDv7 generation (`uuid.v7()`) and parsing | server, core | chosen |
| `simplifile` | File reading and writing | server | chosen; verify rename for atomic writes, else Erlang FFI to `file:rename/2` |
| `polly` | Polling file watcher (Erlang and Node targets) | server | chosen for the prototype; `watchexec` (native events, needs the watchexec binary) is the alternative |
| `jot` | Parsing and rendering djot cell bodies | core | candidate; verify coverage and JavaScript target in spike S5 |
| `gleeunit` | Test runner | all | chosen |
| `qcheck` | Property tests with shrinking | core | chosen |

Browser capabilities that may need bindings (pointer capture, measuring
element sizes): check Lustre's own facilities and existing Gleam bindings
(for example `plinth`) in spikes S1 and S2.

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
