//// The cell dialect: djot through jot, restricted (02-file-format.md, The
//// cell dialect; spike S5).
////
//// Bodies are parsed with jot, and the AST is walked for constructs the
//// dialect forbids. jot drops inline attributes without a trace, so a small
//// source-level check looks for those. Rendering happens in the client from
//// the AST, never through `jot.to_html`.

import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import jot.{
  type Container, type Document, type Inline, BlockQuote, BulletDash, BulletList,
  Code, Codeblock, Delete, Div, Emphasis, Footnote, FullStop, Heading, Image,
  Insert, Linebreak, Link, Mark, MathDisplay, MathInline, NonBreakingSpace,
  NumericOrdinal, OrderedList, Paragraph, RawBlock, Reference, Span, Strong,
  Subscript, Superscript, Symbol, Text, ThematicBreak, Url,
}

pub type Problem {
  ThematicBreakUsed
  RawBlockUsed
  DivUsed
  SpanUsed
  AttributesUsed
  ReferenceLinkUsed
  ReferenceDefinitionUsed
  FootnoteUsed
  MathUsed
  /// Superscript, subscript, insert, delete, mark, symbols and
  /// non-breaking space.
  ExtraUsed
  /// `*` or `+` bullets.
  BulletSpelling
  /// Ordinals other than `1.`.
  OrdinalSpelling
}

pub fn parse(source: String) -> Document {
  jot.parse(source)
}

/// Problems in a cell body, each listed once, in a stable order.
pub fn problems(source: String) -> List(Problem) {
  let doc = parse(source)
  let heading_ids =
    list.filter_map(doc.content, fn(c) {
      case c {
        Heading(attributes:, ..) -> dict.get(attributes, "id")
        _ -> Error(Nil)
      }
    })
  let definitions =
    dict.keys(doc.references)
    |> list.filter(fn(key) { !list.contains(heading_ids, key) })
    |> list.map(fn(_) { ReferenceDefinitionUsed })
  let footnotes = case dict.is_empty(doc.footnotes) {
    True -> []
    False -> [FootnoteUsed]
  }
  let braces = case has_attribute_braces(source) {
    True -> [AttributesUsed]
    False -> []
  }
  list.flatten([
    list.flat_map(doc.content, block),
    definitions,
    footnotes,
    braces,
  ])
  |> list.unique
}

pub fn describe(problem: Problem) -> String {
  case problem {
    ThematicBreakUsed -> "thematic break"
    RawBlockUsed -> "raw block"
    DivUsed -> "div"
    SpanUsed -> "span"
    AttributesUsed -> "attributes"
    ReferenceLinkUsed -> "reference link"
    ReferenceDefinitionUsed -> "reference definition"
    FootnoteUsed -> "footnote"
    MathUsed -> "math"
    ExtraUsed -> "djot syntax outside the dialect"
    BulletSpelling -> "bullet other than -"
    OrdinalSpelling -> "list number other than 1."
  }
}

fn attrs(attributes: Dict(String, String)) -> List(Problem) {
  case dict.is_empty(attributes) {
    True -> []
    False -> [AttributesUsed]
  }
}

fn block(c: Container) -> List(Problem) {
  case c {
    ThematicBreak -> [ThematicBreakUsed]
    RawBlock(..) -> [RawBlockUsed]
    Div(..) -> [DivUsed]
    Paragraph(attributes:, content:) ->
      list.append(attrs(attributes), list.flat_map(content, inline))
    Heading(attributes:, content:, ..) ->
      list.append(
        attrs(dict.delete(attributes, "id")),
        list.flat_map(content, inline),
      )
    Codeblock(attributes:, ..) -> attrs(attributes)
    BlockQuote(attributes:, items:) ->
      list.append(attrs(attributes), list.flat_map(items, block))
    BulletList(style:, items:, ..) ->
      list.append(
        case style {
          BulletDash -> []
          _ -> [BulletSpelling]
        },
        list.flat_map(list.flatten(items), block),
      )
    OrderedList(punctuation:, ordinal:, start:, items:, ..) ->
      list.append(
        case punctuation, ordinal, start {
          FullStop, NumericOrdinal, 1 -> []
          _, _, _ -> [OrdinalSpelling]
        },
        list.flat_map(list.flatten(items), block),
      )
  }
}

fn inline(i: Inline) -> List(Problem) {
  case i {
    Text(_) | Linebreak | Code(_) -> []
    Emphasis(content:) | Strong(content:) -> list.flat_map(content, inline)
    Link(attributes:, content:, destination:)
    | Image(attributes:, content:, destination:) ->
      list.flatten([
        attrs(attributes),
        case destination {
          Url(_) -> []
          Reference(_) -> [ReferenceLinkUsed]
        },
        list.flat_map(content, inline),
      ])
    Span(..) -> [SpanUsed]
    Footnote(..) -> [FootnoteUsed]
    MathInline(..) | MathDisplay(..) -> [MathUsed]
    NonBreakingSpace
    | Delete(..)
    | Insert(..)
    | Mark(..)
    | Superscript(..)
    | Subscript(..)
    | Symbol(..) -> [ExtraUsed]
  }
}

/// Outside code: a `{` at the start of a line or right after a non-space
/// character, or any `{=`, `{+` or `{-`. jot reads these as attributes or
/// edit marks and may drop the text silently.
fn has_attribute_braces(source: String) -> Bool {
  let #(found, _) =
    list.fold(string.split(source, "\n"), #(False, False), fn(acc, l) {
      let #(found, fenced) = acc
      let fence = string.starts_with(string.trim_start(l), "```")
      case found, fenced, fence {
        True, _, _ -> #(True, fenced)
        _, _, True -> #(False, !fenced)
        _, True, _ -> #(False, True)
        _, False, False -> #(braces_in_line(outside_code(l)), False)
      }
    })
  found
}

/// The line with inline code spans removed.
fn outside_code(l: String) -> String {
  string.split(l, "`")
  |> list.index_map(fn(part, i) {
    case i % 2 {
      0 -> part
      _ -> " "
    }
  })
  |> string.join("")
}

fn braces_in_line(l: String) -> Bool {
  let after_text =
    list.window_by_2(string.to_graphemes(" " <> l))
    |> list.any(fn(pair) {
      pair.1 == "{" && string.trim(pair.0) != "" && pair.0 != "\\"
    })
  after_text
  || string.starts_with(string.trim_start(l), "{")
  || string.contains(l, "{=")
  || string.contains(l, "{+")
  || string.contains(l, "{-")
}

/// A link or image destination that is safe to render: a relative path, or
/// an `http`, `https` or `mailto` URL.
pub fn safe_url(url: String) -> Option(String) {
  let url = string.trim(url)
  case scheme(url) {
    None -> Some(url)
    Some("http") | Some("https") | Some("mailto") -> Some(url)
    Some(_) -> None
  }
}

/// Text before the first `:`, unless a `/`, `?` or `#` comes first (then
/// the colon belongs to a relative path). Anything that looks like a scheme
/// counts, so unusual spellings are rejected rather than let through.
fn scheme(url: String) -> Option(String) {
  case string.split_once(url, ":") {
    Error(Nil) -> None
    Ok(#(before, _)) ->
      case
        string.contains(before, "/")
        || string.contains(before, "?")
        || string.contains(before, "#")
      {
        True -> None
        False -> Some(string.lowercase(before))
      }
  }
}
