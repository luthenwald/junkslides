//// The deck's theme.css as far as the server needs it: the list of variants
//// (04-layout.md, Variants), the files it loads (04-layout.md, Export), and the
//// default theme and fonts `junkslides init` writes (D25, D27).

import filepath
import gleam/erlang/application
import gleam/list
import gleam/result
import gleam/string

/// The paths in the theme's `url()` values, in order and without duplicates,
/// as written. Values with a scheme (`data:`, `https:`) or only a fragment
/// (`#x`) name no file and are left out, and so are values in comments.
/// `@import` without `url()` is not read.
pub fn urls(css: String) -> List(String) {
  without_comments(css)
  |> string.split("url(")
  |> list.drop(1)
  |> list.filter_map(url_value)
  |> list.filter(names_a_file)
  |> list.unique
}

fn without_comments(css: String) -> String {
  case string.split_once(css, "/*") {
    Error(Nil) -> css
    Ok(#(before, rest)) ->
      case string.split_once(rest, "*/") {
        Ok(#(_, after)) -> before <> " " <> without_comments(after)
        Error(Nil) -> before
      }
  }
}

/// The value at the start of what follows `url(`: up to the closing quote if
/// it is quoted, else up to `)`.
fn url_value(rest: String) -> Result(String, Nil) {
  let up_to = fn(text, end) {
    string.split_once(text, end) |> result.map(fn(parts) { parts.0 })
  }
  case string.trim_start(rest) {
    "\"" <> quoted -> up_to(quoted, "\"")
    "'" <> quoted -> up_to(quoted, "'")
    bare -> up_to(bare, ")") |> result.map(string.trim)
  }
  |> result.try(fn(value) {
    case value {
      "" -> Error(Nil)
      value -> Ok(value)
    }
  })
}

/// A scheme is a `:` before the first `/`.
fn names_a_file(value: String) -> Bool {
  let head = case string.split_once(value, "/") {
    Ok(#(head, _)) -> head
    Error(Nil) -> value
  }
  !string.starts_with(value, "#") && !string.contains(head, ":")
}

/// The editor's own font and its licence, which ship with junkslides in
/// `priv/fonts` and are served under `/.js/fonts` for the source text. Decks
/// bring their own fonts or name ones the system has (D25).
pub fn fonts_folder() -> Result(String, String) {
  application.priv_directory("junkslides_server")
  |> result.map(filepath.join(_, "fonts"))
  |> result.replace_error("The junkslides_server priv folder is missing.")
}

/// Kept equal to examples/talk/theme.css (checked by a test). The fonts and
/// the look it once declared are in `settings.default_toml` (D27).
pub const default_css =
  "/* Default prototype theme: grayscale, calm. Fonts, colours, sizes and the
   body area come from junkslides.toml; any rule here wins over them. */
:root {
  --js-variants: \"large small quiet emphasis\";
}

.js-cell[data-variant=\"large\"] { font-size: 64px; }
.js-cell[data-variant=\"small\"] { font-size: 24px; }
.js-cell[data-variant=\"emphasis\"] { font-weight: 600; }
"
