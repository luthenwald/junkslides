//// The deck's theme.css as far as the server needs it: the list of variants
//// (04-layout.md, Variants), the files it loads (04-layout.md, Export), and the
//// default theme and fonts `zeno init` writes (D25, D27).

import filepath
import gleam/erlang/application
import gleam/list
import gleam/result
import gleam/string

/// The names in `--zeno-variants: "a b c";`, in order, without duplicates.
/// A theme without the property has no variants.
pub fn variants(css: String) -> List(String) {
  case string.split_once(css, "--zeno-variants") {
    Error(Nil) -> []
    Ok(#(_, rest)) -> {
      // The declaration ends at the first `;` or `}`.
      let value =
        list.fold([";", "}"], rest, fn(value, end) {
          case string.split_once(value, end) {
            Ok(#(before, _)) -> before
            Error(Nil) -> value
          }
        })
      case string.split_once(value, ":") {
        Error(Nil) -> []
        Ok(#(_, value)) ->
          ["\"", "'", "\n", "\t", "\r"]
          |> list.fold(value, fn(value, s) { string.replace(value, s, " ") })
          |> string.split(" ")
          |> list.filter(fn(name) { name != "" })
          |> list.unique
      }
    }
  }
}

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

/// The default fonts and their licences, which ship with Zeno in `priv/fonts`.
/// `zeno init` copies them into a new deck's `fonts/`, where the default
/// zeno.toml names them; the editor serves them under `/.zeno/fonts` for its own text.
pub fn fonts_folder() -> Result(String, String) {
  application.priv_directory("zeno_server")
  |> result.map(filepath.join(_, "fonts"))
  |> result.replace_error("The zeno_server priv folder is missing.")
}

/// Kept equal to examples/talk/theme.css (checked by a test). The fonts and
/// the look it once declared are in `settings.default_toml` (D27).
pub const default_css =
  "/* Default prototype theme: grayscale, calm. Fonts, colours, sizes and the
   body area come from zeno.toml; any rule here wins over them. */
:root {
  --zeno-variants: \"large small quiet emphasis\";
}

.zeno-cell[data-variant=\"large\"] { font-size: 64px; }
.zeno-cell[data-variant=\"small\"] { font-size: 24px; }
.zeno-cell[data-variant=\"emphasis\"] { font-weight: 600; }
"
