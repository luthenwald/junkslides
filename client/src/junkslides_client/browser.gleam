//// What a deck in the page needs from the browser: its storage, to keep
//// the deck across reloads, and a folder the user picks, to read a deck
//// from. Both come from `plinth`, a package of bindings (D35), so there is
//// no script of our own here.

import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import plinth/browser/file
import plinth/browser/file_system.{type DirectoryHandle}
import plinth/browser/web_storage

/// One entry in the site's local storage. Sites under one host share that
/// storage, hence the name.
const key = "junkslides.deck"

/// What `save` kept last, if anything.
pub fn load() -> Result(String, Nil) {
  use storage <- result.try(web_storage.local() |> result.replace_error(Nil))
  case web_storage.get_item(storage, key) {
    Ok(Some(text)) -> Ok(text)
    _ -> Error(Nil)
  }
}

/// Keeps `text`, or nothing any more. Fails with the browser's reason, for
/// example when the storage is full or switched off.
pub fn save(text: Option(String)) -> Result(Nil, String) {
  use storage <- result.try(web_storage.local())
  case text {
    Some(text) -> web_storage.set_item(storage, key, text)
    None -> Ok(web_storage.remove_item(storage, key))
  }
}

/// Asks the user for a folder and reads text files from it: `first`, and
/// then those `more` names from what was read, by path. Gives the folder's
/// name and the files that were there. Fails with the browser's reason
/// when no folder was picked.
pub fn pick(
  first: List(String),
  more: fn(List(#(String, String))) -> List(String),
) -> Promise(Result(#(String, List(#(String, String))), String)) {
  use folder <- promise.try_await(file_system.show_directory_picker())
  use files <- promise.await(read_all(folder, first))
  use rest <- promise.map(read_all(folder, more(files)))
  Ok(#(file_system.name(folder), list.append(files, rest)))
}

/// The picker's reason when the user closed it without a folder.
pub fn cancelled(reason: String) -> Bool {
  case reason {
    "AbortError" <> _ -> True
    _ -> False
  }
}

fn read_all(
  folder: DirectoryHandle,
  paths: List(String),
) -> Promise(List(#(String, String))) {
  list.map(paths, fn(path) {
    read(folder, path) |> promise.map(result.map(_, fn(text) { #(path, text) }))
  })
  |> promise.await_list
  |> promise.map(result.values)
}

/// The text of the file at `path`, below `folder` only.
fn read(folder: DirectoryHandle, path: String) -> Promise(Result(String, Nil)) {
  let segments =
    list.filter(string.split(path, "/"), fn(segment) {
      segment != "" && segment != "."
    })
  walk(folder, segments)
}

fn walk(
  folder: DirectoryHandle,
  segments: List(String),
) -> Promise(Result(String, Nil)) {
  case segments {
    [] | ["..", ..] -> promise.resolve(Error(Nil))
    [name] -> {
      use handle <- promise.try_await(
        file_system.get_file_handle(folder, name, False) |> without_reason,
      )
      use file <- promise.try_await(
        file_system.get_file(handle) |> without_reason,
      )
      file.text(file) |> promise.map(Ok)
    }
    [name, ..rest] -> {
      use inner <- promise.try_await(
        file_system.get_directory_handle(folder, name, False) |> without_reason,
      )
      walk(inner, rest)
    }
  }
}

fn without_reason(
  result: Promise(Result(a, String)),
) -> Promise(Result(a, Nil)) {
  promise.map(result, result.replace_error(_, Nil))
}
