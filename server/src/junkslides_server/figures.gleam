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
    Ok(relative) ->
      case store.read(filepath.join(folder, relative)), last {
        Error(Nil), _ -> File(store.missing, Error("missing"))
        Ok(#(_, hash)), Ok(File(hash: seen, ..) as last) if hash == seen -> last
        Ok(#(bytes, hash)), _ ->
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
/// script or load from elsewhere. A refused drawing is still shown, as a
/// picture.
///
/// The markup is read tag by tag, as a browser reads it inside a page, and
/// only what a drawing is made of gets through: known elements, no
/// attribute whose name starts with `on` whatever separates it from its
/// neighbours, and no link or `url()` that leaves the drawing. The pages'
/// own policies (06-runtime.md, Serving) stand behind this check.
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
        #("image-set(", "it links outside the drawing"),
        #("\u{0}", "it is not text"),
      ],
      fn(pair) { string.contains(lower, pair.0) },
    )
  use Nil <- result.try(case refused, outside_urls(lower) {
    Ok(#(_, why)), _ -> Error(why)
    _, True -> Error(outside)
    _, False -> Ok(Nil)
  })
  use Nil <- result.try(scan("<svg" <> rest))
  Ok(string.drop_start(text, start))
}

const outside = "it links outside the drawing"

const cut_short = "it is cut short"

/// The elements of a drawing, in lower case. Any `fe…` filter primitive and
/// any name with a prefix (`sodipodi:namedview`, `rdf:RDF`) is known too: a
/// page gives a prefixed name no meaning.
const elements = [
  "svg", "g", "defs", "symbol", "use", "switch", "view", "a", "title", "desc",
  "metadata", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
  "text", "tspan", "textpath", "image", "lineargradient", "radialgradient",
  "stop", "clippath", "mask", "pattern", "marker", "filter", "style", "animate",
  "animatetransform", "animatemotion", "mpath", "set",
]

/// Walks the lower-cased markup from one `<` to the next.
fn scan(markup: String) -> Result(Nil, String) {
  case string.split_once(markup, "<") {
    Error(Nil) -> Ok(Nil)
    Ok(#(_, rest)) ->
      case rest {
        "!--" <> rest -> comment(rest) |> result.try(scan)
        "![cdata[" <> rest -> character_data(rest) |> result.try(scan)
        "!" <> _ | "?" <> _ -> Error("it has a declaration inside")
        "/" <> rest ->
          case starts_a_name(rest) {
            True -> tag(rest) |> result.try(fn(read) { scan(read.rest) })
            False -> Error("it has a malformed tag")
          }
        _ ->
          case starts_a_name(rest) {
            // A `<` that starts no tag is text.
            False -> scan(rest)
            True -> {
              use read <- result.try(tag(rest))
              case read.name, read.empty {
                // A page reads what these two hold as HTML, by other rules
                // than a drawing's, so they may hold text only.
                "title", False | "desc", False -> plain(read.name, read.rest)
                _, _ -> scan(read.rest)
              }
            }
          }
      }
  }
}

/// A comment ends at `-->`. The other ways a browser ends one are refused,
/// so that both agree on where it stops.
fn comment(rest: String) -> Result(String, String) {
  case rest, string.split_once(rest, "-->") {
    ">" <> _, _ | "->" <> _, _ -> Error("it has a malformed comment")
    _, Error(Nil) -> Error(cut_short)
    _, Ok(#(body, rest)) ->
      case string.contains(body, "--!>") {
        True -> Error("it has a malformed comment")
        False -> Ok(rest)
      }
  }
}

/// A CDATA section, as stylesheets from drawing programs come in. Without
/// angle brackets inside, it ends at the same place whichever way a browser
/// reads it.
fn character_data(rest: String) -> Result(String, String) {
  case string.split_once(rest, "]]>") {
    Error(Nil) -> Error(cut_short)
    Ok(#(body, rest)) ->
      case string.contains(body, "<") || string.contains(body, ">") {
        True -> Error("it has a CDATA section with angle brackets")
        False -> Ok(rest)
      }
  }
}

/// After `<title>` or `<desc>`: text up to the element's own end tag.
fn plain(name: String, rest: String) -> Result(Nil, String) {
  let closing = "/" <> name
  case string.split_once(rest, "<") {
    Error(Nil) -> Error(cut_short)
    Ok(#(_, after)) ->
      case string.starts_with(after, closing), after {
        True, _ -> scan("<" <> after)
        False, "/" <> _ | False, "!" <> _ | False, "?" <> _ ->
          Error("its " <> name <> " holds markup")
        False, _ ->
          case starts_a_name(after) {
            True -> Error("its " <> name <> " holds markup")
            // A `<` that starts no tag is text here too.
            False -> plain(name, after)
          }
      }
  }
}

type Read {
  /// A tag that passed, and the markup after its `>`. `empty` is True for a
  /// tag closed by `/>`.
  Read(name: String, empty: Bool, rest: String)
}

/// A start or end tag from its name on: the name is a drawing's, and so is
/// every attribute.
fn tag(text: String) -> Result(Read, String) {
  let #(name, rest) = take(text, ["/", ">", ..spaces], "")
  let known =
    list.contains(elements, name)
    || string.starts_with(name, "fe")
    || string.contains(name, ":")
  case known {
    False -> Error("it has an element that is not a drawing's, " <> name)
    True -> attributes(name, rest, False)
  }
}

const spaces = [" ", "\n", "\t", "\r", "\u{c}"]

fn starts_a_name(text: String) -> Bool {
  case string.pop_grapheme(text) {
    Ok(#(first, _)) -> string.contains("abcdefghijklmnopqrstuvwxyz", first)
    Error(Nil) -> False
  }
}

/// The attributes of a tag up to its `>`, read as a browser reads them: a
/// space or a `/` ends one, or the quote that closes its value. `slash` is
/// True right after a `/`.
fn attributes(name: String, text: String, slash: Bool) -> Result(Read, String) {
  case text {
    "" -> Error(cut_short)
    ">" <> rest -> Ok(Read(name:, empty: slash, rest:))
    "/" <> rest -> attributes(name, rest, True)
    " " <> rest
    | "\n" <> rest
    | "\t" <> rest
    | "\r" <> rest
    | "\u{c}" <> rest -> attributes(name, rest, False)
    _ -> {
      let #(key, rest) = take(text, ["=", "/", ">", ..spaces], "")
      use #(value, rest) <- result.try(case skip_spaces(rest) {
        "=" <> rest -> value(skip_spaces(rest))
        _ -> Ok(#("", rest))
      })
      case key {
        "" -> Error("it has a malformed tag")
        _ ->
          attribute(key, string.trim(value))
          |> result.try(fn(_) { attributes(name, rest, False) })
      }
    }
  }
}

/// An attribute's value and the text after it.
fn value(text: String) -> Result(#(String, String), String) {
  case text {
    "\"" <> rest ->
      string.split_once(rest, "\"") |> result.replace_error(cut_short)
    "'" <> rest ->
      string.split_once(rest, "'") |> result.replace_error(cut_short)
    _ -> Ok(take(text, [">", ..spaces], ""))
  }
}

/// Whether a drawing may carry this attribute: no event handler, no link
/// that is not a fragment of the drawing itself, and no animation of a link
/// or a handler.
fn attribute(key: String, value: String) -> Result(Nil, String) {
  let link = key == "src" || string.ends_with(key, "href")
  let animated =
    key == "attributename"
    && { string.contains(value, "href") || string.starts_with(value, "on") }
  case string.starts_with(key, "on"), link, animated {
    True, _, _ -> Error("it has event handler attributes")
    _, True, _ ->
      case string.starts_with(value, "#") {
        True -> Ok(Nil)
        False -> Error(outside)
      }
    _, _, True -> Error("it animates a link")
    _, _, _ -> Ok(Nil)
  }
}

fn skip_spaces(text: String) -> String {
  case text {
    " " <> rest
    | "\n" <> rest
    | "\t" <> rest
    | "\r" <> rest
    | "\u{c}" <> rest -> skip_spaces(rest)
    _ -> text
  }
}

/// The text before the first of `ends`, and the text from there on.
fn take(text: String, ends: List(String), taken: String) -> #(String, String) {
  case list.any(ends, string.starts_with(text, _)) {
    True -> #(taken, text)
    False ->
      case string.pop_grapheme(text) {
        Ok(#(first, rest)) -> take(rest, ends, taken <> first)
        Error(Nil) -> #(taken, "")
      }
  }
}

/// A `url(...)` anywhere, styles included, that is not a fragment of the
/// drawing itself.
fn outside_urls(lower: String) -> Bool {
  string.split(lower, "url(")
  |> list.drop(1)
  |> list.map(string.trim_start)
  |> list.any(fn(value) {
    case value {
      "\"" <> v | "'" <> v -> !string.starts_with(v, "#")
      v -> !string.starts_with(v, "#")
    }
  })
}
