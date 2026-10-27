# S4 files

## Question

Does polly see external edits on macOS quickly enough? Can the server ignore
its own writes by hash? Is the temp-file-and-rename write atomic for readers?

## What was tried

`spikes/s4_files`, with polly 3.1.0, simplifile 2.7.0, gleam_crypto 1.6.0,
Gleam 1.19.2, OTP 29, macOS (APFS). Run with `just s4` (about 75 seconds,
because the polly cases wait for whole-second boundaries).

- `src/store.gleam`: `write_atomic` (temp file in the same folder, synced,
  renamed over the target), `hash` (sha256), and `poll`, a content poller
  that reads the file every 250 ms and reports when its hash changes.
- `src/s4_store_ffi.erl`: `write_synced`, which writes and calls
  `file:sync` before closing. simplifile cannot flush a file.
- `test/s4_files_test.gleam`: the experiments below, with a measurement
  printed for each.

## Results

| Experiment | Result |
|---|---|
| polly, 250 ms, 20 external writes one second apart | all seen, mean 103 to 199 ms, max 142 to 238 ms over two runs |
| polly, two external writes within one second | the second write was missed 5 times out of 5 |
| Content poller, 250 ms, 20 external writes | all seen, mean 128 ms, max 227 ms |
| Own writes by hash (10 own atomic writes interleaved with 10 external writes) | 10 of 10 own writes ignored, 10 of 10 external writes reported |
| Reader racing 500 writes of two 1 MB contents, temp file and rename | 0 torn reads out of 1144 |
| The same race with plain `simplifile.write_bits` (control) | 145 torn reads out of 421 |
| fsync | not in simplifile; `file:sync/1` through a 15-line Erlang FFI works |

### Why polly misses edits

polly keys a file by `max(mtime_seconds, ctime_seconds)` and compares only
that key, with no size, inode or content. simplifile exposes whole seconds
only. So after polly reports a change, any further write in the same
second has the same key, and polly never reports it until a later write
lands in a different second. For Zeno that means an external save made
right after another one (or right after Zeno's own write) can be lost
silently: the server keeps the older text and later overwrites the file
with it. This breaks principle 7 and external edit scenarios 1 and 8.

The cause is the granularity, not macOS. It would happen on any platform.

### Content polling

Reading three small files four times a second and hashing them is cheap.
Decks are kilobytes, and sha256 of 1 MB takes about a millisecond. The poller
also does the own-write check for free: the event carries the hash, and the
state owner compares it with the hash of its last write. A rename by an
editor (vim, many IDEs) changes the content and is seen like any other
write.

## What to use

- Writes: `write_atomic` as in `store.gleam`. Temp file `.deck.md.zeno-tmp`
  in the same folder, synced through the Erlang FFI, then
  `simplifile.rename`. The FFI is one module (`store_ffi.erl`) with one
  function, as CLAUDE.md allows.
- Watching: a content poller of our own (about 30 lines) instead of polly.
  It polls every 250 ms, reports the new hash, and lets the state owner
  ignore hashes it wrote itself.
- Hashing: `gleam_crypto` sha256.

## Consequences for the design

- P18 (polling watcher `polly`) should change to "polling watcher that
  compares content hashes". This is a P default, so I have not changed it.
  It needs your decision.
- 06-runtime.md, "Watching files", step 1 already reads and hashes the file;
  with a content poller, the read happens in the poller.
- 07-stack.md: polly would be dropped, gleam_crypto added for the server,
  simplifile's rename verified (atomic, `file:rename/2`), plus the fsync FFI.
- Not covered: syncing the folder after the rename, for durability across a
  power loss. Erlang's `file` module cannot open a directory for sync, so
  this would need a port program. Atomicity for readers does not depend on
  it. I suggest leaving it out of the prototype.

## Open decisions

- Replace polly with the content poller (P18). Decided 2026-10-27: yes.
