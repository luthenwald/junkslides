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

1. Any change schedules a write.
2. After 300 ms without further changes, read deck.md and layout.json once
   more and handle an outside edit that polling has not seen yet (see
   below). A write never replaces an edit it has not seen.
3. Print the file. If the printed bytes hash to the hash of what is on disk
   (as last read or written), skip.
4. Write to a temporary file in the same folder (`.deck.md.zeno-tmp`), flush it,
   then rename it over the target. Rename within one folder is atomic on POSIX
   file systems, so readers see either the old file or the new one.
5. Record the new hash.

Order: deck.md first, then layout.json. If the process dies in between, the
consistency step on load (02-file-format.md) repairs the layout.

A file with an open problem (deck.md that does not parse or is missing,
layout.json that is not valid) is not written until the problem is gone.
Edits in Zeno go on meanwhile and are kept in memory.

## Watching files

The server watches deck.md, layout.json and theme.css by polling every 250 ms
and hashing the contents (P18). File times are not used: on macOS they have
whole-second resolution here, so two edits within one second would look like
one (spike S4). The same hash tells the server's own writes apart.

When deck.md changes:

1. Read it and hash it. If the hash equals the hash of the bytes last read
   or written, there is nothing new; this is how the server's own writes
   are told apart.
2. Parse it with the reading rules. On a parse error: keep the current state,
   send a `Notice` with the line number, and do not write deck.md until the
   file parses again.
3. On success, compute effects by comparing ID sets with the deck as last
   read from or written to deck.md (the base of the outside edit, not the
   current deck, which may hold unsaved ops): IDs gone are `Retired`, new
   IDs are `Fresh`, IDs found in orphans are `Revived` (and the same for
   slides). Fold them into the layout.
4. If ops were applied since the last write (a write was pending), rebase:
   apply those ops again, in order, on the externally edited deck. Ops whose
   target no longer exists fail; drop them and send a `Notice` listing them.
   Because ops address cells by ID, this is mechanical. Details:
   - Ops are kept in groups, one per `Apply`, with the `IdSupply` that was
     used. A group is replayed with the same supply, so an inserted or
     duplicated cell gets the same ID again and layout ops on it still
     apply. A group is dropped as a whole when one of its ops fails.
   - After the replay the consistency step runs once more. It brings back
     the records of cells that only the replay recreated.
   - An undo or redo that was not saved yet cannot be replayed as ops. The
     outside edit replaces it, and the ops after it, with a `Notice`.
5. Record the result as one history step, broadcast `State`, and write the
   files (the canonical printer adds any missing markers). An outside editor
   that has deck.md open will see the file change on disk; that is expected,
   since markers are machine-maintained. If only formatting changed (the
   parsed deck equals the current one), no step is recorded, but the
   canonical form is still written.

If deck.md disappears while serving, the server keeps the state, sends a
`Notice`, and does not write deck.md until the file is back. Problems that
are still open are also sent to clients that connect later.

When layout.json changes externally: parse and validate it; if valid, replace
the layout (running the consistency step) as one history step; if not, keep
the current layout, send a `Notice`, and do not write layout.json until it is
valid again. A deleted layout.json is written again from memory, since Zeno
owns that file.

When theme.css changes: re-read the variant list and send `ReloadTheme`, and
a new `State` if the list changed. The list is the names inside the quoted
value of `--zeno-variants` (04-layout.md), in order.

## Serving

The server also serves the client bundle, theme.css, and files under the deck
folder for images. Requested paths are resolved and must stay inside the deck
folder; anything else is refused.

| Path | Serves |
|---|---|
| `/` | The page: loads `/theme.css` and `/zeno/client.js` |
| `/ws` | The WebSocket |
| `/zeno/...` | The client bundle, from the server's `priv/static` |
| anything else | A file in the deck folder |

Path segments are percent-decoded, then empty, `.`, `..` and hidden (dot)
segments are refused, which also hides the temporary files of atomic writes.
Symbolic links inside the deck folder are followed; they are the user's own.

## Failure behaviour

- The server never writes a file it could not produce from a valid state.
- A failed write is reported as a `Notice` and retried on the next change.
- If deck.md does not parse at start, `zeno serve` refuses and names the line.
  An invalid layout.json at start is kept on disk; the server starts with an
  empty layout and reports the problem.
- If deck.md is missing at start, `zeno serve` refuses and suggests
  `zeno init`.
