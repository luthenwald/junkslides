import gleam/list
import gleam/option.{None, Some}
import gleam/string
import zeno_client/highlight

fn joined(pieces: List(#(option.Option(String), String))) -> String {
  list.map(pieces, fn(piece) { piece.1 }) |> string.concat
}

pub fn haskell_is_highlighted_test() {
  let code = "-- | entry\nmain :: IO ()\nmain = case x of _ -> pure ()"
  let pieces = highlight.tokens(Some("haskell"), code)
  assert joined(pieces) == code
  assert list.contains(pieces, #(Some("zeno-tok-comment"), "-- | entry"))
  assert list.contains(pieces, #(Some("zeno-tok-operator"), "::"))
  assert list.contains(pieces, #(Some("zeno-tok-keyword"), "case"))
  // The alias and any case work as well.
  assert highlight.tokens(Some("HS"), code) == pieces
}

pub fn unknown_or_missing_languages_stay_plain_test() {
  assert highlight.tokens(Some("klingon"), "a b") == [#(None, "a b")]
  assert highlight.tokens(None, "a b") == [#(None, "a b")]
}
