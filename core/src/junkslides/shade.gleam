//// Shading of code whose language has no tree-sitter grammar (D30): a few
//// plain rules, read left to right, into the token kinds tree-sitter's
//// highlight names use, so a theme styles both alike.
////
//// - a comment marker to the end of the line: `comment`; the markers are
////   `--` and `//` unless junkslides.toml names others
//// - a word (ASCII letters, digits, `_` and `'`, not starting with a digit):
////   `keyword` if it is in the list, `type` if it starts with a capital,
////   else plain; `\case` is a keyword too, as in Haskell
//// - digits: `number`
//// - a run of `-+*/<>=:.|&\$@!?~^%`: `operator`
//// - one of `()[]{},` and the backtick: `punctuation`
//// - anything else, spaces and other scripts included: plain
////
//// Pure; the rules follow the excerpts of the PSaV talk's animations.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import junkslides/protocol.{type Token, Token}

/// How code is shaded by these rules: its keywords, the markers that start a
/// comment, and the languages shaded by them even where a grammar exists
/// (`simple`), such as excerpts that would not parse.
pub type Rules {
  Rules(keywords: List(String), comments: List(String), simple: List(String))
}

/// The comment markers when junkslides.toml names none.
pub const default_comments = ["--", "//"]

/// The rules when junkslides.toml names none.
pub const default_rules = Rules(default_keywords, default_comments, [])

/// The keywords shaded when junkslides.toml names none.
pub const default_keywords = [
  "case", "of", "let", "in", "if", "then", "else", "do", "where", "return",
  "while", "for", "fn", "def", "data", "type", "module", "import",
]

/// The tokens of `code`, covering it exactly. Neighbouring plain text is one
/// token.
pub fn tokens(code: String, rules: Rules) -> List(Token) {
  let ctx = Ctx(rules.keywords, list.map(rules.comments, string.to_graphemes))
  loop(string.to_graphemes(code), ctx, [])
  |> join_plain
}

/// The rules as the loop reads them: comment markers as graphemes.
type Ctx {
  Ctx(keywords: List(String), comments: List(List(String)))
}

fn starts_with(rest: List(String), marker: List(String)) -> Bool {
  case marker, rest {
    [], _ -> True
    [m, ..marker], [g, ..rest] if m == g -> starts_with(rest, marker)
    _, _ -> False
  }
}

fn loop(rest: List(String), ctx: Ctx, done: List(Token)) -> List(Token) {
  let comment =
    rest != []
    && list.any(ctx.comments, fn(m) { m != [] && starts_with(rest, m) })
  case rest {
    [] -> list.reverse(done)
    _ if comment -> {
      let #(comment, rest) = list.split_while(rest, fn(g) { g != "\n" })
      loop(rest, ctx, [token(Some("comment"), comment), ..done])
    }
    ["\\", "c", "a", "s", "e", ..after] ->
      case word_next(after) {
        False -> loop(after, ctx, [Token(Some("keyword"), "\\case"), ..done])
        True -> general(rest, ctx, done)
      }
    _ -> general(rest, ctx, done)
  }
}

fn general(rest: List(String), ctx: Ctx, done: List(Token)) -> List(Token) {
  case rest {
    [] -> list.reverse(done)
    [g, ..] ->
      case is_word_start(g), is_digit(g), is_operator(g), is_punctuation(g) {
        True, _, _, _ -> {
          let #(word, rest) = list.split_while(rest, is_word)
          let text = string.concat(word)
          let kind = case list.contains(ctx.keywords, text), is_capital(g) {
            True, _ -> Some("keyword")
            False, True -> Some("type")
            False, False -> None
          }
          loop(rest, ctx, [Token(kind, text), ..done])
        }
        _, True, _, _ -> {
          let #(digits, rest) = list.split_while(rest, is_digit)
          loop(rest, ctx, [token(Some("number"), digits), ..done])
        }
        _, _, True, _ -> {
          let #(run, rest) = list.split_while(rest, is_operator)
          loop(rest, ctx, [token(Some("operator"), run), ..done])
        }
        _, _, _, True -> plain_or(rest, ctx, done, Some("punctuation"))
        _, _, _, _ -> plain_char(rest, ctx, done)
      }
  }
}

fn word_next(rest: List(String)) -> Bool {
  case rest {
    [g, ..] -> is_word(g)
    [] -> False
  }
}

fn plain_char(rest: List(String), ctx: Ctx, done: List(Token)) -> List(Token) {
  plain_or(rest, ctx, done, None)
}

fn plain_or(
  rest: List(String),
  ctx: Ctx,
  done: List(Token),
  kind: Option(String),
) -> List(Token) {
  case rest {
    [g, ..rest] -> loop(rest, ctx, [Token(kind, g), ..done])
    [] -> list.reverse(done)
  }
}

fn token(kind: Option(String), graphemes: List(String)) -> Token {
  Token(kind, string.concat(graphemes))
}

fn join_plain(tokens: List(Token)) -> List(Token) {
  list.fold(tokens, [], fn(done, t) {
    case t, done {
      Token(None, text), [Token(None, before), ..done] -> [
        Token(None, before <> text),
        ..done
      ]
      _, _ -> [t, ..done]
    }
  })
  |> list.reverse
}

const letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"

const capitals = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

const digits = "0123456789"

const operators = "-+*/<>=:.|&\\$@!?~^%"

const punctuation = "()[]{},`"

fn one_of(set: String, g: String) -> Bool {
  string.length(g) == 1 && string.contains(set, g)
}

fn is_word_start(g: String) -> Bool {
  one_of(letters, g)
}

fn is_word(g: String) -> Bool {
  one_of(letters, g) || one_of(digits, g) || g == "'"
}

fn is_capital(g: String) -> Bool {
  one_of(capitals, g)
}

fn is_digit(g: String) -> Bool {
  one_of(digits, g)
}

fn is_operator(g: String) -> Bool {
  one_of(operators, g)
}

fn is_punctuation(g: String) -> Bool {
  one_of(punctuation, g)
}
