//// The deck's theme.css as far as the server needs it: the list of variants
//// (04-layout.md, Variants) and the default theme `zeno init` writes.

import gleam/list
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

/// Kept equal to examples/talk/theme.css (checked by a test).
pub const default_css =
  "/* Default prototype theme: grayscale, calm. */
:root {
  --zeno-variants: \"large small quiet emphasis\";
}

.zeno-slide {
  background: #fafafa;
  color: #222;
  font: 32px/1.4 system-ui, sans-serif;
}

.zeno-body {
  grid-area: 3 / 3 / 17 / 31;
  gap: 24px;
}

.zeno-cell[data-variant=\"large\"] { font-size: 64px; }
.zeno-cell[data-variant=\"small\"] { font-size: 24px; }
.zeno-cell[data-variant=\"quiet\"] { color: #777; }
.zeno-cell[data-variant=\"emphasis\"] { font-weight: 600; }

/* Code: grayscale highlighting by weight, slant and shade. */
.zeno-tok-keyword { font-weight: 600; }
.zeno-tok-comment { color: #888; font-style: italic; }
.zeno-tok-string { color: #555; }
.zeno-tok-number,
.zeno-tok-constant { color: #444; }
.zeno-tok-type,
.zeno-tok-constructor,
.zeno-tok-module { color: #333; font-style: italic; }
.zeno-tok-function { color: #111; font-weight: 600; }
.zeno-tok-operator,
.zeno-tok-punctuation { color: #999; }
"
