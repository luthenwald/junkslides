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
///
/// A target that is a link stays one: the file it leads to is replaced. The
/// new file keeps the old one's permissions. Each write has a temporary
/// name of its own, so two writers of one file never share it.
pub fn write_atomic(path: String, bytes: BitArray) -> Result(String, String) {
  let path = behind_links(path, 8)
  let unique =
    crypto.strong_random_bytes(4) |> bit_array.base16_encode |> string.lowercase
  let temp =
    filepath.join(
      filepath.directory_name(path),
      "." <> filepath.base_name(path) <> "." <> unique <> ".js-tmp",
    )
  let written = {
    use Nil <- result.try(write_synced(temp, bytes))
    let _ = case simplifile.file_info(path) {
      Ok(info) ->
        simplifile.set_permissions_octal(
          temp,
          simplifile.file_info_permissions_octal(info),
        )
      Error(_) -> Ok(Nil)
    }
    simplifile.rename(temp, path)
    |> result.map_error(simplifile.describe_error)
  }
  case written {
    Ok(Nil) -> Ok(hash(bytes))
    Error(reason) -> {
      let _ = simplifile.delete(temp)
      Error(reason)
    }
  }
}

/// Whether the file at `relative` (from `resolve`) is the deck's own: no
/// symbolic link on the way to it leads out of `folder`. A deck unpacked
/// from someone's archive can hold a link to any file on the machine, which
/// must not travel on into an export. Links that stay inside the deck are
/// fine.
pub fn inside(folder: String, relative: String) -> Bool {
  let #(_, stays) =
    string.split(relative, "/")
    |> list.fold(#(folder, True), fn(acc, segment) {
      let #(parent, stays) = acc
      let path = filepath.join(parent, segment)
      let here = case simplifile.is_symlink(path) {
        Ok(True) -> {
          let target =
            behind_links(path, 8) |> filepath.expand |> result.unwrap("")
          string.starts_with(target, folder <> "/")
        }
        _ -> True
      }
      #(path, stays && here)
    })
  stays
}

/// The file a path leads to through symbolic links, a few at most. A path
/// that is no link is itself.
fn behind_links(path: String, hops: Int) -> String {
  case hops, read_link(path) {
    0, _ | _, Error(Nil) -> path
    _, Ok(target) ->
      case filepath.is_absolute(target) {
        True -> target
        False -> filepath.join(filepath.directory_name(path), target)
      }
      |> behind_links(hops - 1)
  }
}

@external(erlang, "junkslides_server_store_ffi", "write_synced")
fn write_synced(path: String, bytes: BitArray) -> Result(Nil, String)

@external(erlang, "junkslides_server_store_ffi", "read_link")
fn read_link(path: String) -> Result(String, Nil)
