# 06/10 Runtime

## Processes

One local server process per open deck, and one or more browser tabs as
clients.

```
zeno init <folder>     create a deck folder with a minimal deck and default theme
zeno serve <folder>    serve the deck, print the URL (default port 4870)
```

The server binds to 127.0.0.1 only.

## Ownership

The server owns the canonical state:

- the current `Deck` and `Layout`;
- the `History`;
- the hash of the last bytes it wrote to deck.md and to layout.json;
- the ops applied since the last successful write of deck.md (for rebasing,
  see below);
- the theme's variant list.

Clients hold a copy of the state plus transient UI state (selection, the text
being typed, a drag in progress). Clients never write files.

## Protocol

JSON messages over one WebSocket per client. Codecs live in `core`, so client
and server share them.

Client to server:

| Message | Meaning |
|---|---|
| `Hello` | Request the full state |
| `Apply(seq, ops)` | Apply a list of `Op`s atomically (one undo step) |
| `ApplyLayout(seq, op)` | Apply one `LayoutOp` |
| `Undo`, `Redo` | History |
| `SaveView(view)` | Store pane sizes and visibility |

Server to client:

| Message | Meaning |
|---|---|
| `State(version, deck, layout, diagnostics, variants, view)` | Full state |
| `Rejected(seq, reason)` | An op failed; state unchanged |
| `Notice(text)` | Something the user should see (external edit result, parse error) |
| `ReloadTheme` | theme.css changed |

In the prototype the server broadcasts the full `State` after every change.
Decks are small, so this is simple and correct; patches can come later.

## Writing files

1. Any change marks deck.md and/or layout.json dirty.
2. After 300 ms without further changes, print the file.
3. If the printed bytes hash to the last written hash, skip.
4. Write to a temporary file in the same folder (`.deck.md.zeno-tmp`), flush it,
   then rename it over the target. Rename within one folder is atomic on POSIX
   file systems, so readers see either the old file or the new one.
5. Record the new hash.

Order: deck.md first, then layout.json. If the process dies in between, the
consistency step on load (02-file-format.md) repairs the layout.

## Watching files

The server watches deck.md, layout.json and theme.css (polling every 250 ms in
the prototype).

When deck.md changes:

1. Read it and hash it. If the hash equals the last written hash, it is the
   server's own write: ignore.
2. Parse it with the reading rules. On a parse error: keep the current state,
   send a `Notice` with the line number, and do not write deck.md until the
   file parses again.
3. On success, compute effects by comparing ID sets with the current deck:
   IDs gone are `Retired`, new IDs are `Fresh`, IDs found in orphans are
   `Revived` (and the same for slides). Fold them into the layout.
4. If ops were applied since the last write (a write was pending), rebase:
   apply those ops again, in order, on the externally edited deck. Ops whose
   target no longer exists fail; drop them and send a `Notice` listing them.
   Because ops address cells by ID, this is mechanical.
5. Record the result as one history step, broadcast `State`, and write the
   files (the canonical printer adds any missing markers). An outside editor
   that has deck.md open will see the file change on disk; that is expected,
   since markers are machine-maintained.

When layout.json changes externally: parse and validate it; if valid, replace
the layout (running the consistency step) as one history step; if not, keep
the current layout and send a `Notice`.

When theme.css changes: re-read the variant list and send `ReloadTheme`.

## Serving

The server also serves the client bundle, theme.css, and files under the deck
folder for images. Requested paths are resolved and must stay inside the deck
folder; anything else is refused.

## Failure behaviour

- The server never writes a file it could not produce from a valid state.
- A failed write is reported as a `Notice` and retried on the next change.
- If deck.md is missing at start, `zeno serve` refuses and suggests
  `zeno init`.
