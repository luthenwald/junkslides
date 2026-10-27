//// Writing and watching, as candidates for the server's store and watch
//// modules.

import filepath
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process.{type Subject}
import simplifile

pub fn hash(bytes: BitArray) -> String {
  crypto.hash(crypto.Sha256, bytes) |> bit_array.base16_encode
}

/// Write to a temporary file in the same folder, sync it, then rename it
/// over the target.
pub fn write_atomic(path: String, bytes: BitArray) -> Result(Nil, Nil) {
  let temp =
    filepath.join(
      filepath.directory_name(path),
      "." <> filepath.base_name(path) <> ".zeno-tmp",
    )
  case write_synced(temp, bytes) {
    Ok(Nil) ->
      case simplifile.rename(temp, path) {
        Ok(Nil) -> Ok(Nil)
        Error(_) -> Error(Nil)
      }
    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "s4_store_ffi", "write_synced")
pub fn write_synced(path: String, bytes: BitArray) -> Result(Nil, Nil)

/// A content poller: every `interval` ms read the file and send its hash
/// when it differs from the last one seen. Missing files hash as "".
pub fn poll(
  path: String,
  interval: Int,
  events: Subject(String),
) -> Subject(Nil) {
  let ready = process.new_subject()
  process.spawn(fn() {
    let stop = process.new_subject()
    process.send(ready, stop)
    poll_loop(path, interval, events, stop, read_hash(path))
  })
  let assert Ok(stop) = process.receive(ready, 1000)
  stop
}

fn poll_loop(path, interval, events, stop, last: String) -> Nil {
  case process.receive(stop, interval) {
    Ok(Nil) -> Nil
    Error(Nil) -> {
      let now = read_hash(path)
      case now == last {
        True -> Nil
        False -> process.send(events, now)
      }
      poll_loop(path, interval, events, stop, now)
    }
  }
}

pub fn read_hash(path: String) -> String {
  case simplifile.read_bits(path) {
    Ok(bytes) -> hash(bytes)
    Error(_) -> ""
  }
}
