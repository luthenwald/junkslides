//// Reading, hashing and writing the files of a deck folder (06-runtime.md,
//// Writing files and Watching files; spike S4).

import filepath
import gleam/bit_array
import gleam/crypto
import gleam/result
import simplifile

/// The hex sha256 of some bytes. Hashes tell the server's own writes apart
/// from outside edits.
pub fn hash(bytes: BitArray) -> String {
  crypto.hash(crypto.Sha256, bytes) |> bit_array.base16_encode
}

/// The hash a missing file is given.
pub const missing = ""

/// A file's bytes and their hash.
pub fn read(path: String) -> Result(#(BitArray, String), Nil) {
  simplifile.read_bits(path)
  |> result.map(fn(bytes) { #(bytes, hash(bytes)) })
  |> result.replace_error(Nil)
}

/// Writes to a temporary file in the same folder, syncs it, then renames it
/// over the target, so readers see either the old file or the new one.
/// Returns the hash of the bytes written.
pub fn write_atomic(path: String, bytes: BitArray) -> Result(String, String) {
  let temp =
    filepath.join(
      filepath.directory_name(path),
      "." <> filepath.base_name(path) <> ".zeno-tmp",
    )
  use Nil <- result.try(write_synced(temp, bytes))
  use Nil <- result.try(
    simplifile.rename(temp, path)
    |> result.map_error(simplifile.describe_error),
  )
  Ok(hash(bytes))
}

@external(erlang, "zeno_server_store_ffi", "write_synced")
fn write_synced(path: String, bytes: BitArray) -> Result(Nil, String)
