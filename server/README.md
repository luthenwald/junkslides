# zeno_server

The local server of Zeno, on the Erlang target: the `zeno` command, one
owner actor per deck holding the canonical state, the WebSocket protocol,
debounced atomic writes, polling for outside edits, and static files. See
docs/06-runtime.md.

```sh
just zeno init <folder>     # a minimal deck with the default theme
just zeno serve <folder>    # http://127.0.0.1:4870/
just server-test            # unit tests and the external edit scenarios
```

The client bundle is built into `priv/static` in M3; until then the page
at `/` loads only the theme.
