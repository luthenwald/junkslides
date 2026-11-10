//// What a theme.css declares to the editor: its variants (04-layout.md,
//// Variants) and its mark classes (D28).

import gleam/list
import gleam/string

/// The names in `--js-variants: "a b c";`, in order, without duplicates.
/// A theme without the property has no variants.
pub fn variants(css: String) -> List(String) {
  names(css, "--js-variants")
}

/// The mark classes in `--js-marks: "now quiet";`, likewise (D28). A theme
/// without the property has no marks.
pub fn marks(css: String) -> List(String) {
  names(css, "--js-marks")
}

fn names(css: String, property: String) -> List(String) {
  case string.split_once(css, property) {
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
