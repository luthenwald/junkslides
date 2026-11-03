//// The files of the deck's figures (D29; 06-runtime.md, Figures): drawings
//// (`.svg`), drawn inline on the slide, and chart specs (`.json`), drawn by
//// the renderer. The owner reads them as it reads the deck's other files and
//// sends their text to clients; the export reads them once.
////
//// A drawing goes into the page as markup, so it is checked first. One that
//// could run script or reach outside the deck is not inlined but drawn as an
//// `img`, where the browser runs nothing, and the user is told why.

import filepath
import gleam/bit_array
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import zeno/dialect
import zeno_server/store

/// A figure file as last read: its hash, and its text or why it cannot be
/// used.
pub type File {
  File(hash: String, text: Result(String, String))
}

/// Reads the figure at `url`, as a cell writes it, from the deck `folder`.
pub fn read(folder: String, url: String) -> File {
  case store.resolve(string.split(url, "/")) {
    Error(Nil) -> File(store.missing, Error("outside the deck"))
    Ok(relative) ->
      case store.read(filepath.join(folder, relative)) {
        Error(Nil) -> File(store.missing, Error("missing"))
        Ok(#(bytes, hash)) ->
          File(
            hash,
            bit_array.to_string(bytes)
              |> result.replace_error("not UTF-8")
              |> result.try(fn(text) {
                case dialect.figure_kind(url) {
                  Some(dialect.Drawing) -> drawing(text)
                  _ -> Ok(text)
                }
              }),
          )
      }
  }
}

/// The figures a list of files can draw, for the `Figures` message.
pub fn usable(files: List(#(String, File))) -> List(#(String, String)) {
  list.filter_map(files, fn(pair) {
    pair.1.text |> result.map(fn(text) { #(pair.0, text) })
  })
}

/// A notice for a figure that cannot be used.
pub fn problem(url: String, file: File) -> Result(String, Nil) {
  case file.text {
    Ok(_) -> Error(Nil)
    Error(why) -> Ok("The figure " <> url <> " cannot be drawn: " <> why <> ".")
  }
}

/// An SVG file as markup for the page: from its `<svg` on, so that a prolog,
/// doctype or comment before it is left out, if nothing in it could run
/// script or load from elsewhere. The check is by text and errs on the side
/// of refusing; a refused drawing is still shown, as a picture.
pub fn drawing(text: String) -> Result(String, String) {
  let lower = string.lowercase(text)
  use #(_, rest) <- result.try(
    string.split_once(lower, "<svg")
    |> result.replace_error("no <svg> element"),
  )
  let start = string.length(text) - string.length(rest) - 4
  let refused =
    list.find(
      [
        #("<script", "it has a script"),
        #("<foreignobject", "it has foreign content"),
        #("<iframe", "it has a frame"),
        #("<!entity", "it declares entities"),
        #("javascript:", "it has a javascript: link"),
        #("<?xml-stylesheet", "it loads a stylesheet"),
        #("@import", "it imports a stylesheet"),
      ],
      fn(pair) { string.contains(lower, pair.0) },
    )
  let tags = tags(rest)
  case refused, handlers(tags), outside_links(tags, rest) {
    Ok(#(_, why)), _, _ -> Error(why)
    _, True, _ -> Error("it has event handler attributes")
    _, _, True -> Error("it links outside the drawing")
    _, False, False -> Ok(string.drop_start(text, start))
  }
}

/// The insides of the tags, joined by spaces, so that text between tags is
/// not mistaken for attributes.
fn tags(lower: String) -> String {
  string.split(lower, "<")
  |> list.map(fn(piece) {
    case string.split_once(piece, ">") {
      Ok(#(tag, _)) -> tag
      Error(Nil) -> piece
    }
  })
  |> string.join(" ")
}

/// An attribute whose name starts with `on`, such as `onload=`, after a
/// space.
fn handlers(lower: String) -> Bool {
  string.split(lower, "on")
  |> list.window_by_2
  |> list.any(fn(pair) {
    let #(before, after) = pair
    let spaced =
      string.ends_with(before, " ")
      || string.ends_with(before, "\n")
      || string.ends_with(before, "\t")
    let #(name, rest) = take_letters(string.to_graphemes(after), "")
    spaced && name != "" && string.starts_with(string.trim_start(rest), "=")
  })
}

fn take_letters(graphemes: List(String), name: String) -> #(String, String) {
  case graphemes {
    [g, ..rest] ->
      case string.contains("abcdefghijklmnopqrstuvwxyz", g) && g != "" {
        True -> take_letters(rest, name <> g)
        False -> #(name, string.concat(graphemes))
      }
    [] -> #(name, "")
  }
}

/// A `href` or `src` in a tag, or a `url(...)` anywhere (styles included),
/// that is not a fragment of the drawing itself.
fn outside_links(tags: String, lower: String) -> Bool {
  let after = fn(marker) {
    string.split(
      case marker {
        "url(" -> lower
        _ -> tags
      },
      marker,
    )
    |> list.drop(1)
    |> list.map(string.trim_start)
  }
  let attribute_values = fn(name) {
    after(name)
    |> list.filter_map(fn(rest) {
      case string.trim_start(rest) {
        "=" <> value -> Ok(string.trim_start(value))
        _ -> Error(Nil)
      }
    })
    |> list.map(fn(value) {
      case value {
        "\"" <> v | "'" <> v -> v
        v -> v
      }
    })
  }
  let urls =
    after("url(")
    |> list.map(fn(value) {
      case value {
        "\"" <> v | "'" <> v -> v
        v -> v
      }
    })
  list.flatten([attribute_values("href"), attribute_values(" src"), urls])
  |> list.any(fn(value) { !string.starts_with(value, "#") })
}
