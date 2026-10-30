//// Syntax highlighting of code blocks with smalto (D21; 04-layout.md,
//// Theme contract). A code block's language, as written after its fence,
//// picks a grammar; the tokens become `zeno-tok-<kind>` classes for the
//// theme to style. Unknown languages and blocks without one stay plain.

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import smalto
import smalto/grammar.{type Grammar}
import smalto/languages/bash
import smalto/languages/c
import smalto/languages/cpp
import smalto/languages/css
import smalto/languages/elixir
import smalto/languages/erlang
import smalto/languages/gleam
import smalto/languages/go
import smalto/languages/haskell
import smalto/languages/html
import smalto/languages/java
import smalto/languages/javascript
import smalto/languages/json
import smalto/languages/kotlin
import smalto/languages/lua
import smalto/languages/python
import smalto/languages/ruby
import smalto/languages/rust
import smalto/languages/scala
import smalto/languages/sql
import smalto/languages/swift
import smalto/languages/toml
import smalto/languages/typescript
import smalto/languages/xml
import smalto/languages/yaml
import smalto/languages/zig
import smalto/token

/// The text of a code block in pieces, each with the kind of token it is,
/// if any. Joined, the pieces give the text back.
pub fn tokens(
  language: Option(String),
  code: String,
) -> List(#(Option(String), String)) {
  case option.then(language, grammar_for) {
    None -> [#(None, code)]
    Some(grammar) ->
      smalto.to_tokens(code, grammar)
      |> list.map(fn(t) {
        case t {
          token.Whitespace(text) | token.Other(text) -> #(None, text)
          _ -> #(Some(class_name(token.name(t))), value(t))
        }
      })
      |> merge
  }
}

/// Fence names and their common aliases.
fn grammar_for(language: String) -> Option(Grammar) {
  case string.lowercase(string.trim(language)) {
    "haskell" | "hs" -> Some(haskell.grammar())
    "gleam" -> Some(gleam.grammar())
    "python" | "py" -> Some(python.grammar())
    "javascript" | "js" | "mjs" -> Some(javascript.grammar())
    "typescript" | "ts" -> Some(typescript.grammar())
    "rust" | "rs" -> Some(rust.grammar())
    "c" | "h" -> Some(c.grammar())
    "cpp" | "c++" | "cc" | "hpp" -> Some(cpp.grammar())
    "zig" -> Some(zig.grammar())
    "elixir" | "ex" | "exs" -> Some(elixir.grammar())
    "erlang" | "erl" -> Some(erlang.grammar())
    "go" -> Some(go.grammar())
    "java" -> Some(java.grammar())
    "kotlin" | "kt" -> Some(kotlin.grammar())
    "scala" -> Some(scala.grammar())
    "swift" -> Some(swift.grammar())
    "ruby" | "rb" -> Some(ruby.grammar())
    "lua" -> Some(lua.grammar())
    "bash" | "sh" | "shell" | "zsh" -> Some(bash.grammar())
    "sql" -> Some(sql.grammar())
    "json" -> Some(json.grammar())
    "toml" -> Some(toml.grammar())
    "yaml" | "yml" -> Some(yaml.grammar())
    "html" -> Some(html.grammar())
    "xml" -> Some(xml.grammar())
    "css" -> Some(css.grammar())
    _ -> None
  }
}

/// A token kind as a class name: smalto's custom kinds may hold characters
/// a class should not.
fn class_name(kind: String) -> String {
  let safe =
    string.to_graphemes(string.lowercase(kind))
    |> list.map(fn(c) {
      case string.contains("abcdefghijklmnopqrstuvwxyz0123456789-", c) {
        True -> c
        False -> "-"
      }
    })
    |> string.concat
  "zeno-tok-" <> safe
}

fn value(t: token.Token) -> String {
  case t {
    token.Keyword(v)
    | token.String(v)
    | token.Number(v)
    | token.Comment(v)
    | token.Function(v)
    | token.Operator(v)
    | token.Punctuation(v)
    | token.Type(v)
    | token.Module(v)
    | token.Variable(v)
    | token.Constant(v)
    | token.Builtin(v)
    | token.Tag(v)
    | token.Attribute(v)
    | token.Selector(v)
    | token.Property(v)
    | token.Regex(v)
    | token.Whitespace(v)
    | token.Other(v) -> v
    token.Custom(value:, ..) -> value
  }
}

/// Neighbours of the same kind become one piece, so plain text is not cut
/// into many text nodes.
fn merge(
  pieces: List(#(Option(String), String)),
) -> List(#(Option(String), String)) {
  list.fold(pieces, [], fn(done, piece) {
    case done, piece {
      [#(kind, text), ..rest], #(next, more) if kind == next -> [
        #(kind, text <> more),
        ..rest
      ]
      _, _ -> [piece, ..done]
    }
  })
  |> list.reverse
}
