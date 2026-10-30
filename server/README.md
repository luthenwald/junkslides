# zeno_server

The local server of Zeno, on the Erlang target: the `zeno` command, one
owner actor per deck holding the canonical state, the WebSocket protocol,
debounced atomic writes, polling for outside edits, and static files.

```sh
just zeno init <folder>     # a minimal deck with the default theme
just zeno serve <folder>    # http://127.0.0.1:4870/
just server-test            # unit tests and the external edit scenarios
```

The page at `/` loads the client bundle and its stylesheet from
`priv/static`, which `just client` builds from `../client` (`just zeno`
does that first).
