import gleam/list
import gleam/option.{None, Some}
import gleam/string
import zeno/protocol.{CodeBlock, Token}
import zeno_server/highlighter
import zeno_server/shade

const viz_keywords = [
  "case",
  "of",
  "let",
  "in",
  "if",
  "then",
  "else",
  "do",
  "where",
  "return",
]

const viz = shade.Rules(viz_keywords, ["--", "//"], [])

fn kinds(code: String) -> List(#(String, String)) {
  kinds_with(code, viz)
}

fn kinds_with(code: String, rules: shade.Rules) -> List(#(String, String)) {
  shade.tokens(code, rules)
  |> list.filter_map(fn(t) {
    case t.kind {
      Some(kind) -> Ok(#(kind, t.text))
      None -> Error(Nil)
    }
  })
}

pub fn tokens_cover_the_code_test() {
  let code = "next w = \\case\n  Fork kind ss -> do  -- the fork\nπ ∧ ¬pθ\n"
  assert string.concat(list.map(shade.tokens(code, viz), fn(t) { t.text }))
    == code
}

pub fn haskell_as_viz_shades_it_test() {
  assert kinds("data Cmd k = Assign Name Expr k   -- k stays outside")
    == [
      #("type", "Cmd"),
      #("operator", "="),
      #("type", "Assign"),
      #("type", "Name"),
      #("type", "Expr"),
      #("comment", "-- k stays outside"),
    ]
  assert kinds("next w = \\case")
    == [#("operator", "="), #("keyword", "\\case")]
  // `\cases` is an operator and a word.
  assert kinds("\\cases") == [#("operator", "\\")]
  assert kinds("guardE :: Expr -> Exc")
    == [
      #("operator", "::"),
      #("type", "Expr"),
      #("operator", "->"),
      #("type", "Exc"),
    ]
}

pub fn gcl_with_its_comments_test() {
  assert kinds("if a[k] > 0 then { d := 1 } // d is ite")
    == [
      #("keyword", "if"),
      #("punctuation", "["),
      #("punctuation", "]"),
      #("operator", ">"),
      #("number", "0"),
      #("keyword", "then"),
      #("punctuation", "{"),
      #("operator", ":="),
      #("number", "1"),
      #("punctuation", "}"),
      #("comment", "// d is ite"),
    ]
  // A word with a prime or digits is one word; plain text is joined up.
  assert shade.tokens("e'1 x2", viz) == [Token(None, "e'1 x2")]
}

pub fn comment_markers_come_from_the_rules_test() {
  let only_dashes = shade.Rules(viz_keywords, ["--"], [])
  // With `--` alone, `//` is an operator and the words after it are shaded.
  assert kinds_with("x // no OutOfBounds", only_dashes)
    == [#("operator", "//"), #("type", "OutOfBounds")]
  assert kinds_with("x # note", shade.Rules([], ["#"], []))
    == [#("comment", "# note")]
  assert kinds_with("x -- y", shade.Rules([], [], [])) == [#("operator", "--")]
}

/// A language the rules name is shaded by them even where a grammar exists,
/// so an excerpt that would not parse is shaded like the rest.
pub fn simple_languages_skip_their_grammar_test() {
  let code = "data Cmd k = If Expr k   -- k stays outside\n           | ...\n"
  let rules = shade.Rules(viz_keywords, ["--"], ["haskell"])
  let assert [highlight] =
    highlighter.highlight("tree-sitter", [CodeBlock("haskell", code)], rules)
  assert highlight.tokens == shade.tokens(code, rules)
}
