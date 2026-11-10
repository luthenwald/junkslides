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
import junkslides/dialect
import junkslides/drawing
import junkslides_server/store

/// A figure file as last read: its hash, and its text or why it cannot be
/// used.
pub type File {
  File(hash: String, text: Result(String, String))
}

/// Reads the figure at `url`, as a cell writes it, from the deck `folder`.
pub fn read(folder: String, url: String) -> File {
  read_again(folder, url, Error(Nil))
}

/// As `read`, for a figure read before: bytes with the hash of `last` are
/// not checked again, so polling an unchanged drawing costs one read.
pub fn read_again(
  folder: String,
  url: String,
  last: Result(File, Nil),
) -> File {
  case store.resolve(string.split(url, "/")) {
    Error(Nil) -> File(store.missing, Error("outside the deck"))
    Ok(relative) -> {
      let inside = store.inside(folder, relative)
      case store.read(filepath.join(folder, relative)), last {
        Error(Nil), _ -> File(store.missing, Error("missing"))
        // A figure's text goes into the page, and so into an export.
        Ok(#(_, hash)), _ if !inside ->
          File(hash, Error("a link that leads out of the deck"))
        Ok(#(_, hash)), Ok(File(hash: seen, ..) as last) if hash == seen -> last
        Ok(#(bytes, hash)), _ ->
          File(
            hash,
            bit_array.to_string(bytes)
              |> result.replace_error("not UTF-8")
              |> result.try(fn(text) {
                case dialect.figure_kind(url) {
                  Some(dialect.Drawing) -> drawing.safe(text)
                  _ -> Ok(text)
                }
              }),
          )
      }
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
