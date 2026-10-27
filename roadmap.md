# Roadmap progress

Progress tracker. The design roadmap is docs/08-roadmap.md.

## Done

- Toolchain: gleam 1.19.2, Erlang/OTP 29, rebar3 3.28.0 (Homebrew), node 26.
- S5 jot: wrap jot, own line splitter for reading rule 5. See docs/spikes/S5-jot.md.

## Todo

- M0 spikes: S3 socket, S4 files, S1 drag, S2 measure.
- M1 core, M2 server, M3 and M4 client, M5 hardening.

## Next step

Continue M0 with S3 (socket), then S4, S1, S2, following the plan in each
section of docs/08-roadmap.md. Spike code lives in `spikes/sN_name/`, notes in
`docs/spikes/`. Run checks through `just`.

## Log

- 2026-10-27: toolchain installed, scaffolding, S5 done.
