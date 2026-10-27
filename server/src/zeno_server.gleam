//// The `zeno` command (06-runtime.md, Processes).
////
////     zeno init <folder>                 a minimal deck and the default theme
////     zeno serve <folder> [--port N]     serve the deck on 127.0.0.1

import argv
import envoy
import filepath
import gleam/bit_array
import gleam/bool
import gleam/erlang/application
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/result
import logging
import simplifile
import zeno/deck.{Cell, Content, Deck, Slide}
import zeno/file
import zeno/id
import zeno/layout
import zeno_server/state
import zeno_server/store
import zeno_server/theme
import zeno_server/view
import zeno_server/web

const usage =
  "Usage:
  zeno init <folder>               create a deck with the default theme
  zeno serve <folder> [--port N]   serve the deck (default port 4870)"

pub fn main() -> Nil {
  let result = case argv.load().arguments {
    ["init", folder] -> init(folder)
    ["serve", folder] -> serve(folder, 4870)
    ["serve", folder, "--port", port] ->
      case int.parse(port) {
        Ok(port) -> serve(folder, port)
        Error(Nil) -> Error("Not a port number: " <> port)
      }
    _ -> Error(usage)
  }
  case result {
    Ok(Nil) -> Nil
    Error(message) -> {
      io.println_error(message)
      halt(1)
    }
  }
}

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

/// Creates the folder if needed and writes deck.md, layout.json and
/// theme.css. An existing deck.md is never replaced; existing layout.json
/// and theme.css files are kept.
pub fn init(folder: String) -> Result(Nil, String) {
  let folder = absolute(folder)
  let deck_path = filepath.join(folder, "deck.md")
  use <- bool.guard(
    simplifile.is_file(deck_path) == Ok(True),
    Error("There is a deck.md in " <> folder <> " already."),
  )
  use Nil <- result.try(
    simplifile.create_directory_all(folder)
    |> result.map_error(simplifile.describe_error),
  )
  let #(slide, supply) = id.fresh(state.new_supply(), id.empty_set())
  let #(cell, _) = id.fresh(supply, id.insert(id.empty_set(), slide))
  let deck = Deck([Slide(slide, [Cell(cell, Content, "# Untitled")])])
  use _ <- result.try(store.write_atomic(deck_path, text(file.print(deck))))
  use Nil <- result.try(write_new(
    filepath.join(folder, "layout.json"),
    file.print_layout(layout.empty()),
  ))
  use Nil <- result.try(write_new(
    filepath.join(folder, "theme.css"),
    theme.default_css,
  ))
  io.println("Created a deck in " <> folder <> ".")
  io.println("Run: zeno serve " <> folder)
  Ok(Nil)
}

fn write_new(path: String, contents: String) -> Result(Nil, String) {
  case simplifile.is_file(path) {
    Ok(True) -> Ok(Nil)
    _ -> store.write_atomic(path, text(contents)) |> result.replace(Nil)
  }
}

pub fn serve(folder: String, port: Int) -> Result(Nil, String) {
  let folder = absolute(folder)
  use owner <- result.try(state.start(state.config(folder, view_file())))
  use client <- result.try(
    application.priv_directory("zeno_server")
    |> result.map(filepath.join(_, "static"))
    |> result.replace_error("The zeno_server priv folder is missing."),
  )
  // A port in use makes the listener's supervisor log a long report and
  // exit, which would take this process with it, before the start returns
  // its error. The message below says it plainly instead.
  logging.set_level(logging.Emergency)
  process.trap_exits(True)
  let started = web.start(web.Config(port:, folder:, client:), owner)
  process.trap_exits(False)
  logging.set_level(logging.Notice)
  use _ <- result.try(
    started
    |> result.replace_error(
      "Could not listen on 127.0.0.1:"
      <> int.to_string(port)
      <> ". Is the port in use, perhaps by another zeno serve? Pick another with --port N.",
    ),
  )
  io.println("Serving " <> folder)
  io.println("http://127.0.0.1:" <> int.to_string(port) <> "/")
  process.sleep_forever()
  Ok(Nil)
}

fn view_file() -> String {
  view.default_file(envoy.get("HOME") |> result.unwrap("."))
}

fn absolute(folder: String) -> String {
  case filepath.is_absolute(folder) {
    True -> folder
    False ->
      case simplifile.current_directory() {
        Ok(cwd) -> filepath.join(cwd, folder)
        Error(_) -> folder
      }
  }
  |> filepath.expand
  |> result.unwrap(folder)
}

fn text(contents: String) -> BitArray {
  bit_array.from_string(contents)
}
