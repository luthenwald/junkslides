//// Syntax highlighting of code blocks with the user's tree-sitter (D21;
//// 06-runtime.md, Highlighting). The command runs in this actor, so the
//// deck's owner is never held up by it. A block's language picks a grammar
//// among those `tree-sitter dump-languages` lists; a language without one,
//// or a machine without tree-sitter, is shaded by `shade` (D30).

import envoy
import filepath
import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import junkslides/protocol.{
  type CodeBlock, type Highlight, type Token, Highlight, Token,
}
import junkslides_server/shade
import shellout
import simplifile

pub type Message {
  /// Highlights for these blocks, sent back whole to `reply`. Nothing is
  /// sent when the answer is the same as the last one.
  /// `rules` shade the blocks without a grammar, and those of the languages
  /// they name (D30).
  Request(
    blocks: List(CodeBlock),
    rules: shade.Rules,
    reply: fn(List(Highlight)) -> Nil,
  )
}

type State {
  State(
    command: String,
    temporary: String,
    /// From a fence's language to a grammar's scope.
    scopes: Dict(String, String),
    /// The tokens of the last request's blocks. A block that cannot be
    /// highlighted is kept with no tokens, so it is not tried again.
    known: Dict(CodeBlock, List(Token)),
    sent: List(Highlight),
    rules: shade.Rules,
  )
}

/// The grammars the command knows. An error means it could not be run.
pub fn languages(command: String) -> Result(Dict(String, String), Nil) {
  shellout.command(run: command, with: ["dump-languages"], in: ".", opt: [])
  |> result.map(parse_languages)
  |> result.replace_error(Nil)
}

pub fn start(command: String) -> Result(Subject(Message), Nil) {
  let scopes = languages(command) |> result.unwrap(dict.new())
  actor.new(State(
    command,
    temporary_file(),
    scopes,
    dict.new(),
    [],
    shade.default_rules,
  ))
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.replace_error(Nil)
}

/// Highlights for these blocks at once, for a caller that can wait. A block
/// that stays plain has no entry.
pub fn highlight(
  command: String,
  blocks: List(CodeBlock),
  rules: shade.Rules,
) -> List(Highlight) {
  let scopes = languages(command) |> result.unwrap(dict.new())
  let state = State(command, temporary_file(), scopes, dict.new(), [], rules)
  list.filter_map(blocks, fn(block) {
    case run(state, block) {
      [] -> Error(Nil)
      tokens -> Ok(Highlight(block, tokens))
    }
  })
}

fn temporary_file() -> String {
  let suffix = crypto.strong_random_bytes(8) |> bit_array.base16_encode
  envoy.get("TMPDIR")
  |> result.unwrap("/tmp")
  |> filepath.join("js-highlight-" <> suffix)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  let Request(blocks:, rules:, reply:) = message
  // Other rules shade the blocks differently.
  let state = case rules == state.rules {
    True -> state
    False -> State(..state, rules:, known: dict.new())
  }
  let known =
    list.map(blocks, fn(block) {
      case dict.get(state.known, block) {
        Ok(tokens) -> #(block, tokens)
        Error(Nil) -> #(block, run(state, block))
      }
    })
  let highlights =
    list.filter_map(known, fn(pair) {
      case pair.1 {
        [] -> Error(Nil)
        tokens -> Ok(Highlight(pair.0, tokens))
      }
    })
  case highlights == state.sent {
    True -> Nil
    False -> reply(highlights)
  }
  actor.continue(State(..state, known: dict.from_list(known), sent: highlights))
}

/// The block's tokens, or none when it stays plain. A language without a
/// grammar, or one the rules name, is shaded by the simple rules.
fn run(state: State, block: CodeBlock) -> List(Token) {
  let simple = list.contains(state.rules.simple, block.language)
  case dict.get(state.scopes, block.language), simple {
    Ok(scope), False -> run_tree_sitter(state, block, scope)
    _, _ -> shade.tokens(block.code, state.rules)
  }
}

fn run_tree_sitter(
  state: State,
  block: CodeBlock,
  scope: String,
) -> List(Token) {
  {
    use Nil <- result.try(
      simplifile.write(state.temporary, block.code) |> result.replace_error(Nil),
    )
    let output =
      shellout.command(
        run: state.command,
        with: [
          "highlight", state.temporary, "--html", "--css-classes", "--scope",
          scope,
        ],
        in: ".",
        opt: [],
      )
    let _ = simplifile.delete(state.temporary)
    use html <- result.try(output |> result.replace_error(Nil))
    tokens_of(html, block.code)
  }
  |> result.unwrap([])
}

// Parsing the command's output --------------------------------------------------

/// From `dump-languages`: blocks of `key: value` lines, one per grammar. A
/// fence may use a grammar's name, its scope with or without `source.`, or
/// one of its file types.
pub fn parse_languages(output: String) -> Dict(String, String) {
  string.split(output, "\n\n")
  |> list.flat_map(fn(entry) {
    let fields =
      string.split(entry, "\n")
      |> list.filter_map(string.split_once(_, ": "))
    let field = fn(key) { list.key_find(fields, key) |> result.unwrap("") }
    case field("scope") {
      "" -> []
      scope -> {
        let plain = case scope {
          "source." <> rest -> rest
          _ -> scope
        }
        [field("name"), scope, plain, ..file_types(field("file_types"))]
        |> list.filter(fn(name) { name != "" })
        |> list.map(fn(name) { #(name, scope) })
      }
    }
  })
  |> dict.from_list
}

/// `["hs", "hs-boot"]` as a list.
fn file_types(value: String) -> List(String) {
  ["[", "]", "\"", " "]
  |> list.fold(value, fn(text, char) { string.replace(text, char, "") })
  |> string.split(",")
}

/// The tokens in the table of `tree-sitter highlight --html --css-classes`.
/// Spans nest, and the innermost one names the text; `punctuation bracket`
/// becomes the kind `punctuation.bracket`. The result must give the code
/// back, or it is not trusted.
pub fn tokens_of(html: String, code: String) -> Result(List(Token), Nil) {
  use #(_, rest) <- result.try(string.split_once(html, "<table>"))
  use #(table, _) <- result.try(string.split_once(rest, "</table>"))
  let tokens = walk(table, Walk([], [], False)) |> merge
  let text = list.map(tokens, fn(token) { token.text }) |> string.concat
  case string.trim_end(text) == string.trim_end(code) {
    True -> Ok(tokens)
    False -> Error(Nil)
  }
}

type Walk {
  /// `line` is True inside a row's code cell, where text counts.
  Walk(done: List(Token), kinds: List(String), line: Bool)
}

fn walk(html: String, at: Walk) -> List(Token) {
  case string.split_once(html, "<") {
    Error(Nil) -> list.reverse(at.done)
    Ok(#(text, rest)) -> {
      let at = add_text(at, text)
      case string.split_once(rest, ">") {
        Error(Nil) -> list.reverse(at.done)
        Ok(#(tag, rest)) -> walk(rest, add_tag(at, tag))
      }
    }
  }
}

fn add_text(at: Walk, text: String) -> Walk {
  case at.line, text {
    False, _ | _, "" -> at
    True, _ -> {
      let kind = case at.kinds {
        [kind, ..] -> Some(kind)
        [] -> None
      }
      Walk(..at, done: [Token(kind, unescape(text)), ..at.done])
    }
  }
}

fn add_tag(at: Walk, tag: String) -> Walk {
  case tag {
    "td class=line" -> Walk(..at, line: True)
    "/td" -> Walk(..at, line: False)
    "/span" -> Walk(..at, kinds: list.drop(at.kinds, 1))
    "span class='" <> rest -> {
      let kind = rest |> string.replace("'", "") |> string.replace(" ", ".")
      Walk(..at, kinds: [kind, ..at.kinds])
    }
    _ -> at
  }
}

fn unescape(text: String) -> String {
  text
  |> string.replace("&lt;", "<")
  |> string.replace("&gt;", ">")
  |> string.replace("&quot;", "\"")
  |> string.replace("&#39;", "'")
  |> string.replace("&amp;", "&")
}

/// Neighbours of one kind become one token, and white space takes no kind.
fn merge(tokens: List(Token)) -> List(Token) {
  list.fold(tokens, [], fn(done, token) {
    let token = case string.trim(token.text) {
      "" -> Token(None, token.text)
      _ -> token
    }
    case done {
      [Token(kind, text), ..rest] if kind == token.kind -> [
        Token(kind, text <> token.text),
        ..rest
      ]
      _ -> [token, ..done]
    }
  })
  |> list.reverse
}
