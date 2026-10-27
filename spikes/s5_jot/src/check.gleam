//// Prototype of the wrapper: walks jot's AST and lists constructs that the
//// dialect forbids. Constructs jot drops silently cannot be seen here.

import gleam/dict.{type Dict}
import gleam/list
import jot.{
  type Container, type Document, type Inline, BlockQuote, BulletDash, BulletList,
  Code, Codeblock, Delete, Div, Emphasis, Footnote, FullStop, Heading, Image,
  Insert, Linebreak, Link, Mark, MathDisplay, MathInline, NonBreakingSpace,
  NumericOrdinal, OrderedList, Paragraph, RawBlock, Reference, Span, Strong,
  Subscript, Superscript, Symbol, Text, ThematicBreak, Url,
}

pub fn problems(doc: Document) -> List(String) {
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
    |> list.map(fn(_) { "reference definition" })
  let footnotes = case dict.is_empty(doc.footnotes) {
    True -> []
    False -> ["footnote definition"]
  }
  list.flatten([list.flat_map(doc.content, block), definitions, footnotes])
}

fn attrs(attributes: Dict(String, String)) -> List(String) {
  case dict.is_empty(attributes) {
    True -> []
    False -> ["attributes"]
  }
}

fn block(c: Container) -> List(String) {
  case c {
    ThematicBreak -> ["thematic break"]
    RawBlock(..) -> ["raw block"]
    Div(..) -> ["div"]
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
          _ -> ["bullet spelling"]
        },
        list.flat_map(list.flatten(items), block),
      )
    OrderedList(punctuation:, ordinal:, items:, ..) ->
      list.append(
        case punctuation, ordinal {
          FullStop, NumericOrdinal -> []
          _, _ -> ["ordinal spelling"]
        },
        list.flat_map(list.flatten(items), block),
      )
  }
}

fn inline(i: Inline) -> List(String) {
  case i {
    Text(_) | Linebreak | Code(_) -> []
    Emphasis(content:) | Strong(content:) -> list.flat_map(content, inline)
    Link(attributes:, content:, destination:)
    | Image(attributes:, content:, destination:) ->
      list.flatten([
        attrs(attributes),
        case destination {
          Url(_) -> []
          Reference(_) -> ["reference link"]
        },
        list.flat_map(content, inline),
      ])
    NonBreakingSpace -> ["non-breaking space"]
    Span(..) -> ["span"]
    Delete(..) | Insert(..) | Mark(..) -> ["edit mark"]
    Superscript(..) | Subscript(..) -> ["super or subscript"]
    Footnote(..) -> ["footnote"]
    MathInline(..) | MathDisplay(..) -> ["math"]
    Symbol(..) -> ["symbol"]
  }
}
