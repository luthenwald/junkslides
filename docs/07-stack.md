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
| `lustre` | Client UI (Elm architecture) | client | chosen; 5.7.1 |
| `lustre_dev_tools` | Building and bundling the client | client (dev) | chosen; 2.4.0 bundles with Bun into `server/priv/static/zeno_client.js` (named after the entry module) and copies `client/assets/` along |
| `gleam_javascript` | `promise.wait`, the client's timers (typing pause, reconnect) | client | chosen; 1.0.1 |
| `mist` | HTTP server and WebSocket | server | chosen; round trip verified in S3 |
| `lustre_websocket` | WebSocket from the Lustre client | client | chosen (D17); ships its own small JS FFI. No reconnect logic, the client calls `init` again on close |
| `gleam_json` | Codecs for protocol, layout.json, view state | core | chosen |
| `youid` | UUIDv7 generation and parsing | none | not needed: `IdSupply` in core makes UUIDv7 from a time and random bits passed in, and `id.gleam` parses UUIDs itself |
| `simplifile` | File reading and writing | server | chosen; `rename` is `file:rename/2` and atomic for readers (S4). No fsync: a one-function Erlang FFI calls `file:sync/1` |
| `gleam_crypto` | sha256 of written and watched files; random bits for `IdSupply` | server | chosen (S4) |
| `jot` | Parsing djot cell bodies | core | chosen (S5): 12.x, covers the dialect on both targets; used through a wrapper that walks the AST for diagnostics. Rendering goes from the AST to Lustre elements, never through `to_html` |
| `gleeunit` | Test runner | all | chosen |
| `simplifile` (dev, core) | Reading `examples/talk` and fixtures in core tests | core (dev) | used on both targets |
| `qcheck` | Property tests with shrinking | core | chosen; 1.0.5 |
| `gleam_time` | `Timestamp` for orphans and coalescing, RFC 3339 in layout.json | core | chosen; 1.11.0 |
| `stratus` | WebSocket client for server tests and the CDP driver | server (dev), e2e | chosen (S3); 3.0.0 |
| `gleam_otp`, `gleam_erlang` | The deck owner actor, timers, subjects | server | chosen; 1.3.0 each |
| `argv` | Command line arguments of `zeno` | server | chosen; 1.1.0 |
| `envoy` | `HOME`, for the view state file | server | chosen; 1.2.0 |
| `filepath` | Joining and expanding paths | server | chosen; 1.1.2 |
| `gleam_httpc` | HTTP requests in server tests and the CDP driver | server (dev), e2e | chosen; 5.0.0 |

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
      id.gleam          Id, tags, IdSupply, IdSet
      line.gleam        structural lines of deck.md
      deck.gleam        Kind, Cell, Slide, Deck, Position, invariants
      op.gleam          Op, Effect, apply, normalize_edit, OpError
      layout.gleam      Area, CellRecord, Layout, LayoutOp, fold_effects,
                        consistency, external edits
      history.gleam     snapshots, undo, redo, coalescing
      dialect.gleam     cell body validation via jot, URL sanitising
      blocks.gleam      splitting unmarked text into blocks (reading rule 5)
      file.gleam        deck.md parse and print, layout.json parse and print
      codec.gleam       JSON for decks, ops and layouts
      protocol.gleam    client/server messages and codecs
    test/
  server/      Erlang target (package zeno_server)
    src/
      zeno_server.gleam CLI entry: init, serve
      zeno_server/
        state.gleam     owner actor: state, history, polling, rebase, writes
        store.gleam     hashing, atomic writes
        web.gleam       HTTP, WebSocket, static files
        theme.gleam     variants from theme.css, the default theme
        view.gleam      per-user view state
      zeno_server_store_ffi.erl   write and fsync (the one Erlang FFI)
    priv/static/        the client bundle and its stylesheet, built by
                        `just client`, not in version control
    test/
  client/      JavaScript target (package zeno_client)
    src/
      zeno_client.gleam main: mounts the app on #app
      zeno_client/
        app.gleam       model, messages, update: socket, selection, modes,
                        clipboard, sending ops
        ui.gleam        the screen: panes, divider, cells pane, status line
        nav.gleam       selection and the positions keys act on (pure)
        keymap.gleam    the keymap, in one place (pure)
        edit.gleam      drafts to ops, split position (pure)
    assets/zeno.css     the editor's styles
    test/               the pure modules, on JavaScript
  e2e/         Erlang target (package zeno_e2e): the editor in headless
               Chrome against an in-process server
    src/cdp.gleam       the DevTools protocol driver
    test/
  examples/
    talk/        a sample deck used in development and integration tests
```

`server` and `client` depend on `core` by path. The module list is a
suggestion; the package boundaries are not.

Watching has no module of its own: the owner actor polls on its own timer,
so reading a file, comparing hashes and applying the edit happen in one
process, in order with client messages.

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
  the external edit scenarios in 08-roadmap.md, with a client connected over
  the WebSocket (stratus). The poll interval and quiet period are shortened
  in tests. Run with `just server-test`.
- `client`: kept thin; logic that can live in `core` should. What is
  client-only but pure (navigation, keymap, drafts) lives in its own modules
  and is unit tested on JavaScript: `just client-test`.
- `e2e`: the editor in headless Chrome against an in-process server
  (`state.start` and `web.start`) on a copy of `examples/talk`, checking the
  page through the DOM and the files on disk. `just e2e` builds the client
  and starts Chrome on port 9334.
- Browser checks: Chrome for Testing (headless shell, kept outside the repo
  in `~/Library/Caches/zeno-cft/`) is driven over the DevTools protocol from
  Gleam, using only the DOM, Input, Page and Emulation domains (and
  `Page.captureScreenshot` to look at the page while working). See
  `e2e/src/cdp.gleam`; the spikes keep their own copy in `spikes/browser`.
  Synthetic input is paced by one frame. Safari is not covered.

## Client techniques

- Keyboard focus without JavaScript: the element that should have focus
  carries `autofocus` with a counter as its value. Lustre calls `focus()`
  whenever that attribute is added to an element or its value changes, and
  focusing scrolls the element into view.
- Text areas are controlled (S2): the one being edited shows the draft from
  the model, the others the deck's text, and each grows with the mirror
  technique.
- The divider is dragged with the hit-strip approach of S1: while dragging,
  an overlay of one strip per percent reports `pointerenter`.
