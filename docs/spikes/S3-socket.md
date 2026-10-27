# S3 socket

## Question

Does a mist WebSocket round trip work with a codec shared from a core
package, compiled once for Erlang and once for JavaScript?

## What was tried

`spikes/s3_socket`:

- `shared`: `Msg { Ping(n) Pong(n) }` with a `gleam_json` 3.1.0 codec, and
  round-trip and wire-format tests on both targets.
- `server`: mist 6.0.3 on 127.0.0.1 serves the client bundle and a WebSocket
  at `/ws` that answers `Ping(n)` with `Pong(n + 1)`.
- `client`: Lustre 5.7.1 with `lustre_websocket` 1.1.0. A button sends
  `Ping`, and each reply is decoded with the shared codec and listed.

Checks:

- `just s3-test`: the codec on both targets, and an Erlang round trip with
  the `stratus` 3.0.0 WebSocket client against the running server.
- `just browser-test` (`spikes/browser/test/s3_test.gleam`): Chrome for
  Testing 156 loads the client, clicks twice, and sees `pong 2` and
  `pong 3`.

## Results

| Check | Result |
|---|---|
| Codec on Erlang and JavaScript | pass (including 2^53 - 1) |
| Erlang client to mist server | pass |
| Lustre client in Chrome to mist server | pass |

- `server` and `client` depend on `shared` by path, which is what
  07-stack.md plans for `core`.
- The one browser binding needed is `lustre_websocket`. It is a Gleam
  package with a 25-line `ffi.mjs` of its own (open, send, close, and
  reading `document.URL` to resolve `/ws`). It has no reconnect logic: on
  `OnClose` the client has to call `init` again itself.
- mist's handler API (`mist.websocket` with `on_init`, `on_close` and a
  handler returning `mist.continue`) maps directly onto the state-owner
  design in 06-runtime.md. Each socket gets a process that can subscribe
  to state broadcasts through the selector returned by `on_init`.

## What to use

- `gleam_json` codecs in `core`, tested on both targets (planned already).
- mist for the server.
- For the client socket: `lustre_websocket`, if third-party bindings are
  acceptable (see below).

## Consequences for the design

None. 06-runtime.md's protocol works as written. Reconnecting after a
server restart is client logic in M3.

## Open decisions

- The client WebSocket binding. Decided 2026-10-27: `lustre_websocket`
  (D17). The options were:
  1. `lustre_websocket` (third-party Gleam package with its own small JS
     FFI). It works today and is my recommendation.
  2. Lustre server components, which have Lustre's own WebSocket transport.
     That would be a different architecture (rendering on the server), not
     just a binding.
  3. A minimal JS FFI of our own. CLAUDE.md rules it out unless you decide
     otherwise.
