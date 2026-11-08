# junkslides_server

The local server of junkslides, on the Erlang target: the `junkslides`
command, one owner actor per deck holding the canonical state, the WebSocket
protocol, debounced atomic writes, polling for outside edits, and static
files.

```sh
just junkslides init <folder>     # a minimal deck with the default theme
just junkslides serve <folder>    # http://127.0.0.1:4870/
just junkslides export <folder>   # a static folder, by default <folder>/export
just server-test            # unit tests and the external edit scenarios
```

The page at `/` loads the client bundle and its stylesheet from
`priv/static`, which `just client` builds from `../client` (`just junkslides`
does that first).
