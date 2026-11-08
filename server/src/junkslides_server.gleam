//// The `junkslides` command (06-runtime.md, Processes).
////
////     junkslides init <folder>                 a minimal deck, default settings and theme
////     junkslides serve <folder> [--port N]     serve the deck on 127.0.0.1
////     junkslides export <folder> [--out path] [--pdf]
////                                        write the deck as a static folder,
////                                        with a PDF of it on request

import argv
import envoy
import filepath
import gleam/bit_array
import gleam/bool
import gleam/erlang/application
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import junkslides/deck.{Cell, Content, Deck, Slide}
import junkslides/file
import junkslides/id
import junkslides/layout
import junkslides_server/export
import junkslides_server/highlighter
import junkslides_server/pdf
import junkslides_server/settings
import junkslides_server/state
import junkslides_server/store
import junkslides_server/theme
import junkslides_server/view
import junkslides_server/web
import logging
import simplifile

const usage =
  "Usage:
  junkslides init <folder>               create a deck with default settings and theme
  junkslides serve <folder> [--port N]   serve the deck (default port 4870)
  junkslides export <folder> [--out P] [--pdf]
                                   write a static page (default <folder>/export),
                                   and with --pdf a PDF of it, using Chrome"

pub fn main() -> Nil {
  let result = case argv.load().arguments {
    ["init", folder] -> init(folder)
    ["serve", folder] -> serve(folder, 4870)
    ["serve", folder, "--port", port] ->
      case int.parse(port) {
        Ok(port) -> serve(folder, port)
        Error(Nil) -> Error("Not a port number: " <> port)
      }
    ["export", folder, ..options] ->
      export_options(options, None, False)
      |> result.try(fn(chosen) {
        let #(out, wants_pdf) = chosen
        case wants_pdf {
          False -> export_deck(folder, out, "tree-sitter")
          True -> {
            use browser <- result.try(pdf.find())
            export_pdf(folder, out, "tree-sitter", browser)
          }
        }
      })
      |> result.map(print_report)
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

fn export_options(
  options: List(String),
  out: Option(String),
  wants_pdf: Bool,
) -> Result(#(Option(String), Bool), String) {
  case options {
    [] -> Ok(#(out, wants_pdf))
    ["--pdf", ..rest] -> export_options(rest, out, True)
    ["--out", path, ..rest] -> export_options(rest, Some(path), wants_pdf)
    _ -> Error(usage)
  }
}

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

/// Creates the folder if needed and writes deck.md, layout.json, junkslides.toml
/// and theme.css. An existing deck.md is never replaced; the other files are
/// kept when they exist.
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
  // The default settings name the default fonts in the deck, so they come
  // with them. Settings that are already there keep their own fonts.
  let settings_path = filepath.join(folder, "junkslides.toml")
  use Nil <- result.try(case simplifile.is_file(settings_path) {
    Ok(True) -> Ok(Nil)
    _ -> {
      use Nil <- result.try(copy_default_fonts(folder))
      write_new(settings_path, settings.default_toml)
    }
  })
  use Nil <- result.try(write_new(
    filepath.join(folder, "theme.css"),
    theme.default_css,
  ))
  io.println("Created a deck in " <> folder <> ".")
  io.println("Run: junkslides serve " <> folder)
  Ok(Nil)
}

/// Copies the fonts that come with junkslides into `fonts/`, apart from files of the same name already there.
fn copy_default_fonts(folder: String) -> Result(Nil, String) {
  let target = filepath.join(folder, "fonts")
  use fonts <- result.try(theme.fonts_folder())
  use files <- result.try(
    simplifile.read_directory(fonts)
    |> result.map_error(simplifile.describe_error),
  )
  use Nil <- result.try(
    simplifile.create_directory_all(target)
    |> result.map_error(simplifile.describe_error),
  )
  list.try_each(files, fn(file) {
    let path = filepath.join(target, file)
    case simplifile.is_file(path) {
      Ok(True) -> Ok(Nil)
      _ ->
        simplifile.copy_file(filepath.join(fonts, file), path)
        |> result.map_error(simplifile.describe_error)
    }
  })
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
  case highlighter.languages("tree-sitter") {
    Ok(_) -> Nil
    Error(Nil) ->
      io.println("tree-sitter was not found, so code blocks are drawn plain.")
  }
  use client <- result.try(
    application.priv_directory("junkslides_server")
    |> result.map(filepath.join(_, "static"))
    |> result.replace_error("The junkslides_server priv folder is missing."),
  )
  use fonts <- result.try(theme.fonts_folder())
  // A port in use makes the listener's supervisor log a long report and
  // exit, which would take this process with it, before the start returns
  // its error. The message below says it plainly instead.
  logging.set_level(logging.Emergency)
  process.trap_exits(True)
  let started = web.start(web.Config(port:, folder:, client:, fonts:), owner)
  process.trap_exits(False)
  logging.set_level(logging.Notice)
  use _ <- result.try(
    started
    |> result.replace_error(
      "Could not listen on 127.0.0.1:"
      <> int.to_string(port)
      <> ". Is the port in use, perhaps by another junkslides serve? Pick another with --port N.",
    ),
  )
  io.println("Serving " <> folder)
  io.println("http://127.0.0.1:" <> int.to_string(port) <> "/")
  process.sleep_forever()
  Ok(Nil)
}

/// Exports what is on disk, and writes nothing in the deck itself. A deck.md
/// or layout.json that does not read stops it before anything is written.
pub fn export_deck(
  folder: String,
  out: Option(String),
  tree_sitter: String,
) -> Result(export.Report, String) {
  let folder = absolute(folder)
  let out = export_folder(folder, out)
  use #(deck, layout) <- result.try(read_deck(folder))
  export.write(folder:, out:, deck:, layout:, tree_sitter:)
}

/// As `export_deck`, and prints the page to a PDF with `browser`.
pub fn export_pdf(
  folder: String,
  out: Option(String),
  tree_sitter: String,
  browser: String,
) -> Result(export.Report, String) {
  let folder = absolute(folder)
  let out = export_folder(folder, out)
  use #(deck, layout) <- result.try(read_deck(folder))
  export.write_pdf(folder:, out:, deck:, layout:, tree_sitter:, browser:)
}

fn export_folder(folder: String, out: Option(String)) -> String {
  option.map(out, absolute) |> option.unwrap(export.default_out(folder))
}

fn read_deck(folder: String) -> Result(#(deck.Deck, layout.Layout), String) {
  use #(bytes, _) <- result.try(
    store.read(filepath.join(folder, "deck.md"))
    |> result.replace_error("There is no deck.md in " <> folder <> "."),
  )
  use deck <- result.try(state.parse_deck(bytes))
  use layout <- result.try(
    case store.read(filepath.join(folder, "layout.json")) {
      Error(Nil) -> Ok(layout.empty())
      Ok(#(bytes, _)) ->
        state.parse_layout(bytes)
        |> result.replace_error(
          "layout.json is not valid, so nothing was exported.",
        )
    },
  )
  Ok(#(deck, layout))
}

fn print_report(report: export.Report) -> Nil {
  list.each(report.warnings, io.println)
  io.println("Exported to " <> report.page)
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
