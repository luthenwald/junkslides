# zeno_e2e

The editor in headless Chrome for Testing against an in-process server, on
a copy of examples/talk. The page is driven over the DevTools protocol from
Gleam (`src/cdp.gleam`) and checked through the DOM and the files on disk.

```sh
just e2e    # builds the client, starts Chrome on port 9334, runs the tests
```
