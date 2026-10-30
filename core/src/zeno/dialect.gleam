//// The cell dialect: djot through jot, restricted (02-file-format.md, The
//// cell dialect; spike S5).
////
//// Bodies are parsed with jot, and the AST is walked for constructs the
//// dialect forbids. jot drops inline attributes without a trace, so a small
//// source-level check looks for those. Rendering happens in the client from
//// the AST, never through `jot.to_html`.

import gleam/dict.{type Dict}
import gleam/int
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
import zeno/blocks

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

// Line structure ---------------------------------------------------------------

/// The indentation of the continuation lines of a cell body, one list per
/// top-level block (split as `blocks.split` does, which matches jot's
/// top-level blocks), in source order (04-layout.md, Line structure).
///
/// A continuation line is a line of text that follows another in the same
/// paragraph, heading or list item; jot turns each into a soft break or,
/// after a trailing backslash, a hard one, and drops its leading spaces.
/// Its indent here counts from the content column of the line that started
/// the text: for `# ( forward` that is 2, so `    execution` on the next
/// line is indented by 2. Block quote markers count as part of the margin,
/// and so do the `#`s a heading's continuation may repeat. Lines inside
/// code fences are never continuations.
pub fn continuation_indents(source: String) -> List(List(Int)) {
  blocks.split(source)
  |> list.map(fn(block) {
    let lines = string.split(block, "\n")
    let first = case lines {
      [first, ..] -> margin(first).1
      [] -> ""
    }
    let kind = case heading_marker(first), item_marker(first) {
      Some(_), _ -> HeadingBlock
      None, Some(_) -> ListBlock
      None, None -> OtherBlock
    }
    let scan =
      list.fold(lines, Scan([], None, False), fn(scan, line) {
        scan_line(scan, line, kind)
      })
    list.reverse(scan.indents)
  })
}

type BlockKind {
  HeadingBlock
  ListBlock
  OtherBlock
}

type Scan {
  /// `column` is the content column of the text being continued, if any.
  Scan(indents: List(Int), column: Option(Int), fence: Bool)
}

fn scan_line(scan: Scan, line: String, kind: BlockKind) -> Scan {
  let #(margin, rest) = margin(line)
  let fence = string.starts_with(rest, "```")
  case scan.fence, fence, rest, scan.column {
    True, True, _, _ -> Scan(..scan, fence: False, column: None)
    True, False, _, _ -> scan
    False, True, _, _ -> Scan(..scan, fence: True, column: None)
    False, False, "", _ -> Scan(..scan, column: None)
    False, False, _, None ->
      Scan(..scan, column: Some(start_column(margin, rest)))
    False, False, _, Some(column) ->
      case kind, item_marker(rest) {
        // Only in a list does a marker start a new item.
        ListBlock, Some(_) ->
          Scan(..scan, column: Some(start_column(margin, rest)))
        // A heading's continuation may repeat its `#`s.
        HeadingBlock, _ -> continued(scan, start_column(margin, rest), column)
        _, _ -> continued(scan, margin, column)
      }
  }
}

fn continued(scan: Scan, at: Int, column: Int) -> Scan {
  Scan(..scan, indents: [int.max(0, at - column), ..scan.indents])
}

/// Leading spaces and block quote markers, and the rest of the line.
fn margin(line: String) -> #(Int, String) {
  margin_loop(line, 0)
}

fn margin_loop(line: String, width: Int) -> #(Int, String) {
  case line {
    " " <> rest -> margin_loop(rest, width + 1)
    "> " <> rest -> margin_loop(rest, width + 2)
    ">" <> rest -> margin_loop(rest, width + 1)
    _ -> #(width, line)
  }
}

/// Where the text of a line that starts a paragraph, heading or list item
/// begins: after its margin and any heading or list marker.
fn start_column(margin: Int, rest: String) -> Int {
  let marker =
    heading_marker(rest)
    |> option.lazy_or(fn() { item_marker(rest) })
    |> option.unwrap(0)
  let #(spaces, _) = margin_loop(string.drop_start(rest, marker), 0)
  margin + marker + spaces
}

/// The width of `#`s and the space after them.
fn heading_marker(rest: String) -> Option(Int) {
  let hashes = count_prefix(rest, "#", 0)
  case hashes > 0 && string.starts_with(string.drop_start(rest, hashes), " ") {
    True -> Some(hashes + 1)
    False -> None
  }
}

/// The width of a list marker and the space after it: `- `, `* `, `+ `,
/// `1. ` or `1) `.
fn item_marker(rest: String) -> Option(Int) {
  case rest {
    "- " <> _ | "* " <> _ | "+ " <> _ -> Some(2)
    _ -> {
      let digits = count_digits(rest, 0)
      let after = string.drop_start(rest, digits)
      case
        digits > 0
        && {
          string.starts_with(after, ". ") || string.starts_with(after, ") ")
        }
      {
        True -> Some(digits + 2)
        False -> None
      }
    }
  }
}

fn count_prefix(text: String, prefix: String, n: Int) -> Int {
  case string.starts_with(text, prefix) {
    True -> count_prefix(string.drop_start(text, 1), prefix, n + 1)
    False -> n
  }
}

fn count_digits(text: String, n: Int) -> Int {
  case string.pop_grapheme(text) {
    Ok(#(c, rest)) ->
      case string.contains("0123456789", c) {
        True -> count_digits(rest, n + 1)
        False -> n
      }
    Error(Nil) -> n
  }
}
