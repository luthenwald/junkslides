# junkslides_core

The pure core of junkslides, shared by the server (Erlang) and the client
(JavaScript): IDs, the deck, operations and their effects, layout, history,
the cell dialect, deck.md and layout.json, and the protocol codecs.

No I/O, no clock, no randomness: fresh IDs come from an `IdSupply` and the
time from a `now` argument.

```sh
just core-test   # both targets
```
