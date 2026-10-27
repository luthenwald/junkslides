# zeno_core

The pure core of Zeno, shared by the server (Erlang) and the client
(JavaScript): IDs, the deck, operations and their effects, layout, history,
the cell dialect, deck.md and layout.json, and the protocol codecs. See
docs/03-data-model.md.

No I/O, no clock, no randomness: fresh IDs come from an `IdSupply` and the
time from a `now` argument.

```sh
just core-test   # both targets
```
