# Working on Zeno

Zeno is a slide maker: content as cells in a strict djot-flavoured text file,
layout edited visually and remembered separately, keyed by stable cell IDs.
The design is complete for the prototype; the code does not exist yet.

## Read first

Read in this order before writing code:

1. README.md
2. docs/01-overview.md
3. docs/03-data-model.md (the heart of the project)
4. docs/02-file-format.md
5. docs/08-roadmap.md (what to build, in what order)
6. docs/09-decisions.md (what is decided and must not change silently)

Then the rest as needed: 04-layout, 05-editor, 06-runtime, 07-stack.

## Hard constraints

- Gleam only. Server on the Erlang target, client on the JavaScript target
  with Lustre, shared `core` package for both.
- No handwritten JavaScript or TypeScript. If a browser capability seems to
  need JavaScript FFI, stop and report the options (existing Gleam bindings,
  a CSS-only approach, a design change, or a minimal FFI) and wait for a
  decision.
- Small Erlang FFI on the server is acceptable when no Gleam library covers
  the need; keep it in one module per concern and document it.
- `core` is pure: no I/O, no clock, no randomness. IDs come from an `IdSupply`
  argument; time comes from a `now` argument.
- Never weaken an `Id` type to a plain String outside `core/src/zeno/id.gleam`.
- Decisions in docs/09-decisions.md are not changed without asking. Defaults
  marked P.. may be questioned; write the case down and ask.

## Order of work

Follow docs/08-roadmap.md: spikes S1 to S5 first, each ending with a note in
`docs/spikes/`. Then M1 core, M2 server, M3 and M4 client, M5 hardening.

M1 is done only when every law in docs/03-data-model.md passes as a qcheck
property on both targets. Do not start UI milestones before that.

## Testing

- `core`: `gleam test --target erlang` and `gleam test --target javascript`.
- Property tests for every law; unit tests for each op and for the parser and
  printer, including the example deck in `examples/talk`.
- `server`: the external edit scenarios listed in docs/08-roadmap.md.

## Files on disk are sacred

- Never write a file that was not produced by the canonical printer from a
  valid state.
- Writes go to a temporary file in the same folder, then rename.
- On a parse error of an externally edited file, keep the last good state and
  do not write.

## Style

- UI: grayscale values only, minimal (docs/05-editor.md, Visual style).
- Docs and comments: plain and calm; avoid em dashes and bold text.
- When the implementation teaches something that changes the design, update
  the relevant doc in the same change.
