//// Shading of code whose language has no tree-sitter grammar (D30): a few
//// plain rules, read left to right, into the token kinds tree-sitter's
//// highlight names use, so a theme styles both alike.
////
//// - `--` or `//` to the end of the line: `comment`
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
import zeno/protocol.{type Token, Token}

/// The keywords shaded when zeno.toml names none.
pub const default_keywords = [
  "case", "of", "let", "in", "if", "then", "else", "do", "where", "return",
  "while", "for", "fn", "def", "data", "type", "module", "import",
]

/// The tokens of `code`, covering it exactly. Neighbouring plain text is one
/// token.
pub fn tokens(code: String, keywords: List(String)) -> List(Token) {
  loop(string.to_graphemes(code), keywords, [])
  |> join_plain
}

fn loop(
  rest: List(String),
  keywords: List(String),
  done: List(Token),
) -> List(Token) {
  case rest {
    [] -> list.reverse(done)
    ["-", "-", ..] | ["/", "/", ..] -> {
      let #(comment, rest) = list.split_while(rest, fn(g) { g != "\n" })
      loop(rest, keywords, [token(Some("comment"), comment), ..done])
    }
    ["\\", "c", "a", "s", "e", ..after] ->
      case word_next(after) {
        False ->
          loop(after, keywords, [Token(Some("keyword"), "\\case"), ..done])
        True -> general(rest, keywords, done)
      }
    _ -> general(rest, keywords, done)
  }
}

fn general(
  rest: List(String),
  keywords: List(String),
  done: List(Token),
) -> List(Token) {
  case rest {
    [] -> list.reverse(done)
    [g, ..] ->
      case is_word_start(g), is_digit(g), is_operator(g), is_punctuation(g) {
        True, _, _, _ -> {
          let #(word, rest) = list.split_while(rest, is_word)
          let text = string.concat(word)
          let kind = case list.contains(keywords, text), is_capital(g) {
            True, _ -> Some("keyword")
            False, True -> Some("type")
            False, False -> None
          }
          loop(rest, keywords, [Token(kind, text), ..done])
        }
        _, True, _, _ -> {
          let #(digits, rest) = list.split_while(rest, is_digit)
          loop(rest, keywords, [token(Some("number"), digits), ..done])
        }
        _, _, True, _ -> {
          let #(run, rest) = list.split_while(rest, is_operator)
          loop(rest, keywords, [token(Some("operator"), run), ..done])
        }
        _, _, _, True -> plain_or(rest, keywords, done, Some("punctuation"))
        _, _, _, _ -> plain_char(rest, keywords, done)
      }
  }
}

fn word_next(rest: List(String)) -> Bool {
  case rest {
    [g, ..] -> is_word(g)
    [] -> False
  }
}

fn plain_char(
  rest: List(String),
  keywords: List(String),
  done: List(Token),
) -> List(Token) {
  plain_or(rest, keywords, done, None)
}

fn plain_or(
  rest: List(String),
  keywords: List(String),
  done: List(Token),
  kind: Option(String),
) -> List(Token) {
  case rest {
    [g, ..rest] -> loop(rest, keywords, [Token(kind, g), ..done])
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
