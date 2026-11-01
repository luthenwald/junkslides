//// Reading, hashing and writing the files of a deck folder (06-runtime.md,
//// Writing files and Watching files; spike S4).

import filepath
import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/result
import gleam/string
import gleam/uri
import simplifile

/// A relative path that stays inside the folder it is joined to. Segments
/// are percent-decoded first, then checked: no empty, `.` or `..` segments,
/// no hidden files (such as the temporary files of atomic writes), no
/// separators or NUL inside a segment.
pub fn resolve(segments: List(String)) -> Result(String, Nil) {
  use segments <- result.try(list.try_map(segments, uri.percent_decode))
  let allowed = fn(segment) {
    segment != ""
    && !string.starts_with(segment, ".")
    && !string.contains(segment, "/")
    && !string.contains(segment, "\\")
    && !string.contains(segment, "\u{0}")
  }
  case segments != [] && list.all(segments, allowed) {
    True -> Ok(string.join(segments, "/"))
    False -> Error(Nil)
  }
}

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
