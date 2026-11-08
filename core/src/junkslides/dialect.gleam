//// The cell dialect: djot through jot, restricted (02-file-format.md, The
//// cell dialect; spike S5).
////
//// Bodies are parsed with jot, and the AST is walked for constructs the
//// dialect forbids. jot drops inline attributes without a trace, so a small
//// source-level check looks for those. Rendering happens in the client from
//// the AST, never through `jot.to_html`.
////
//// jot has no tables, and reads a pipe table as a paragraph. Such a block is
//// recognised here from its source and its cells parsed on their own
//// (`top_level`, 02-file-format.md, Tables).

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import jot.{
  type Container, type Document, type Inline, BlockQuote, BulletDash, BulletList,
  Code, Codeblock, Delete, Div, Emphasis, Footnote, FullStop, Heading, Image,
  Insert, Linebreak, Link, Mark, MathDisplay, MathInline, NonBreakingSpace,
  NumericOrdinal, OrderedList, Paragraph, RawBlock, Reference, Span, Strong,
  Subscript, Superscript, Symbol, Text, ThematicBreak, Url,
}
import junkslides/blocks

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
  /// A table row without its closing pipe or with another number of cells
  /// than the header, or a second separator line.
  TableShape
  /// A mark class (a span's or a code block's) that the theme does not list
  /// in `--js-marks`.
  UnknownMark
  /// A code block attribute other than `lit` with line numbers, or a mark
  /// class with two different delimiter characters.
  CodeAttribute
}

/// A table's cells hold inline content only. The table is rectangular:
/// `head` and every row have as many cells as `columns`, the short ones
/// padded with empty cells. `regular` is False if that took any repair.
pub type Table {
  Table(
    columns: List(ColumnAlign),
    head: List(List(Inline)),
    rows: List(List(List(Inline))),
    regular: Bool,
  )
}

pub type ColumnAlign {
  /// The separator cell has no colon: `---`.
  AlignDefault
  AlignStart
  AlignCenter
  AlignEnd
}

/// A top-level block of a cell body.
pub type Block {
  /// A block as jot read it, with the indents of its continuation lines.
  Contained(container: Container, lines: List(Int))
  Tabular(table: Table)
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
    list.flat_map(top_level(source), fn(top) {
      case top {
        Contained(container:, ..) -> block(container)
        Tabular(table:) -> table_problems(table)
      }
    }),
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
    SpanUsed -> "span without a class"
    AttributesUsed -> "attributes"
    ReferenceLinkUsed -> "reference link"
    ReferenceDefinitionUsed -> "reference definition"
    FootnoteUsed -> "footnote"
    MathUsed -> "math"
    ExtraUsed -> "djot syntax outside the dialect"
    BulletSpelling -> "bullet other than -"
    OrdinalSpelling -> "list number other than 1."
    TableShape -> "table row that does not fit the header"
    UnknownMark -> "mark the theme does not list"
    CodeAttribute ->
      "code attribute other than lit or a mark with two characters"
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
    Codeblock(attributes:, ..) ->
      case code_marks(attributes) {
        Ok(_) -> []
        Error(Nil) -> [CodeAttribute]
      }
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

fn table_problems(table: Table) -> List(Problem) {
  let shape = case table.regular {
    True -> []
    False -> [TableShape]
  }
  [table.head, ..table.rows]
  |> list.flatten
  |> list.flatten
  |> list.flat_map(inline)
  |> list.append(shape)
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
    Span(attributes:, content:) ->
      list.append(span_attributes(attributes), list.flat_map(content, inline))
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

/// A span may carry classes and nothing else (D28): `[120]{.now}`. Which
/// classes the theme knows is checked by `unknown_marks`.
fn span_attributes(attributes: Dict(String, String)) -> List(Problem) {
  case dict.to_list(attributes) {
    [] -> [SpanUsed]
    [#("class", _)] -> []
    _ -> [AttributesUsed]
  }
}

/// Outside code: a `{` at the start of a line or right after a non-space
/// character other than the `]` that closes a span, or any `{=`, `{+` or
/// `{-`. jot reads these as attributes or edit marks and may drop the text
/// silently. A line of attributes right before a code fence is the fence's
/// (D28), checked on the AST instead.
fn has_attribute_braces(source: String) -> Bool {
  let lines = string.split(source, "\n")
  let next = list.append(list.drop(lines, 1), [""])
  let #(found, _) =
    list.fold(list.zip(lines, next), #(False, False), fn(acc, pair) {
      let #(l, after) = pair
      let #(found, fenced) = acc
      let fence = is_fence(l)
      case found, fenced, fence {
        True, _, _ -> #(True, fenced)
        _, _, True -> #(False, !fenced)
        _, True, _ -> #(False, True)
        _, False, False ->
          case fence_attributes(l, after) {
            True -> #(False, False)
            False -> #(braces_in_line(outside_code(l)), False)
          }
      }
    })
  found
}

fn is_fence(l: String) -> Bool {
  string.starts_with(string.trim_start(l), "```")
}

fn fence_attributes(l: String, after: String) -> Bool {
  let l = string.trim(l)
  string.starts_with(l, "{")
  && string.ends_with(l, "}")
  && !string.contains(string.drop_start(l, 1), "{")
  && is_fence(after)
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
      pair.1 == "{"
      && string.trim(pair.0) != ""
      && pair.0 != "\\"
      && pair.0 != "]"
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

// Marks -------------------------------------------------------------------------

/// The mark classes a cell body uses, each once, in order of appearance: the
/// classes of its spans at any depth, in table cells too (D28).
pub fn marks(source: String) -> List(String) {
  list.flat_map(top_level(source), fn(block) {
    case block {
      Contained(container:, ..) -> container_marks(container)
      Tabular(table:) ->
        [table.head, ..table.rows]
        |> list.flatten
        |> list.flat_map(inline_marks)
    }
  })
  |> list.unique
}

/// `[UnknownMark]` if the body uses a mark class not in `known`, the theme's
/// `--js-marks`; else nothing.
pub fn unknown_marks(source: String, known: List(String)) -> List(Problem) {
  case list.all(marks(source), list.contains(known, _)) {
    True -> []
    False -> [UnknownMark]
  }
}

fn container_marks(c: Container) -> List(String) {
  case c {
    Paragraph(content:, ..) | Heading(content:, ..) -> inline_marks(content)
    Codeblock(attributes:, ..) ->
      case code_marks(attributes) {
        Ok(CodeMarks(marks:, ..)) -> list.map(marks, fn(mark) { mark.class })
        Error(Nil) -> []
      }
    BlockQuote(items:, ..) | Div(items:, ..) ->
      list.flat_map(items, container_marks)
    BulletList(items:, ..) | OrderedList(items:, ..) ->
      list.flat_map(items, list.flat_map(_, container_marks))
    _ -> []
  }
}

fn inline_marks(content: List(Inline)) -> List(String) {
  list.flat_map(content, fn(i) {
    case i {
      Span(attributes:, content:) ->
        list.append(span_classes(attributes), inline_marks(content))
      Emphasis(content)
      | Strong(content)
      | Link(content:, ..)
      | Delete(content)
      | Insert(content)
      | Mark(content)
      | Superscript(content)
      | Subscript(content) -> inline_marks(content)
      _ -> []
    }
  })
}

/// The classes of a span, from jot's `class` attribute.
pub fn span_classes(attributes: Dict(String, String)) -> List(String) {
  dict.get(attributes, "class")
  |> result.unwrap("")
  |> string.split(" ")
  |> list.filter(fn(name) { name != "" })
}

// Code blocks ------------------------------------------------------------------

/// The code blocks of a cell body that name a language, as pairs of language
/// and text, at any depth. The text is as drawn: without mark delimiters.
pub fn code_blocks(source: String) -> List(#(String, String)) {
  list.flat_map(parse(source).content, block_code)
}

fn block_code(c: Container) -> List(#(String, String)) {
  case c {
    Codeblock(language: Some(language), content:, attributes:) -> [
      #(language, marked_code(content, code_marks_or_none(attributes)).0),
    ]
    BlockQuote(items:, ..) | Div(items:, ..) -> list.flat_map(items, block_code)
    BulletList(items:, ..) | OrderedList(items:, ..) ->
      list.flat_map(items, list.flat_map(_, block_code))
    _ -> []
  }
}

// Code attributes ---------------------------------------------------------------

/// What a code block's attribute line asks for (D28): its lit lines, counted
/// from 1, and its marks, each a class with an opening and a closing
/// delimiter.
pub type CodeMarks {
  CodeMarks(lit: List(Int), marks: List(CodeMark))
}

pub type CodeMark {
  CodeMark(class: String, open: String, close: String)
}

/// A piece of a code block's text: inside a mark or not, never across a line.
pub type Marked {
  Marked(mark: Option(String), text: String)
}

/// The attribute line of a code block as `CodeMarks`: `lit="2 5-7"` (spaces
/// or commas between numbers and ranges), and any other key a mark class
/// whose value is two different characters, such as `now="⟦⟧"`.
pub fn code_marks(attributes: Dict(String, String)) -> Result(CodeMarks, Nil) {
  dict.to_list(attributes)
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> list.try_fold(CodeMarks([], []), fn(acc, pair) {
    case pair {
      #("lit", value) -> {
        use lit <- result.map(line_numbers(value))
        CodeMarks(..acc, lit:)
      }
      #("class", _) | #("id", _) -> Error(Nil)
      #(class, value) ->
        case string.to_graphemes(value) {
          [open, close] if open != close && open != " " && close != " " ->
            Ok(
              CodeMarks(..acc, marks: [
                CodeMark(class, open, close),
                ..acc.marks
              ]),
            )
          _ -> Error(Nil)
        }
    }
  })
  |> result.map(fn(m) { CodeMarks(..m, marks: list.reverse(m.marks)) })
}

pub fn code_marks_or_none(attributes: Dict(String, String)) -> CodeMarks {
  code_marks(attributes) |> result.unwrap(CodeMarks([], []))
}

fn line_numbers(value: String) -> Result(List(Int), Nil) {
  string.replace(value, ",", " ")
  |> string.split(" ")
  |> list.filter(fn(part) { part != "" })
  |> list.try_map(fn(part) {
    case string.split(part, "-") {
      [one] -> int.parse(one) |> result.map(fn(n) { [n] })
      [from, to] -> {
        use from <- result.try(int.parse(from))
        use to <- result.try(int.parse(to))
        case from <= to {
          True -> Ok(int.range(from, to + 1, [], list.prepend) |> list.reverse)
          False -> Error(Nil)
        }
      }
      _ -> Error(Nil)
    }
  })
  |> result.map(list.flatten)
  |> result.try(fn(lines) {
    case lines != [] && list.all(lines, fn(n) { n >= 1 }) {
      True -> Ok(list.unique(lines))
      False -> Error(Nil)
    }
  })
}

/// A code block's text without its mark delimiters, and the same text in
/// pieces by mark. A mark ends at its closing delimiter or at the end of its
/// line; marks do not nest, so inside one the other delimiters are text.
pub fn marked_code(
  content: String,
  marks: CodeMarks,
) -> #(String, List(Marked)) {
  case marks.marks {
    [] -> #(content, [Marked(None, content)])
    _ -> {
      let pieces =
        string.split(content, "\n")
        |> list.map(marked_line(_, marks.marks))
        |> list.intersperse([Marked(None, "\n")])
        |> list.flatten
        |> list.filter(fn(piece) { piece.text != "" })
      #(string.concat(list.map(pieces, fn(piece) { piece.text })), pieces)
    }
  }
}

fn marked_line(line: String, marks: List(CodeMark)) -> List(Marked) {
  let #(done, current, open) =
    list.fold(string.to_graphemes(line), #([], [], None), fn(acc, g) {
      let #(done, current, open) = acc
      let flush = fn(mark) {
        [Marked(mark, current |> list.reverse |> string.concat), ..done]
      }
      case open {
        Some(CodeMark(close:, class:, ..)) if g == close -> #(
          flush(Some(class)),
          [],
          None,
        )
        Some(_) -> #(done, [g, ..current], open)
        None ->
          case list.find(marks, fn(mark) { mark.open == g }) {
            Ok(mark) -> #(flush(None), [], Some(mark))
            Error(Nil) -> #(done, [g, ..current], None)
          }
      }
    })
  let last =
    Marked(
      option.map(open, fn(mark) { mark.class }),
      current |> list.reverse |> string.concat,
    )
  list.reverse([last, ..done])
}

// Figures -----------------------------------------------------------------------

/// What an image path draws, by its extension (D29). Other images are
/// pictures, drawn as `img`.
pub type FigureKind {
  /// `.svg`: drawn inline, so the theme's rules and fonts reach it.
  Drawing
  /// `.json`: a chart spec junkslides draws.
  Chart
  /// `.html`: a page in a frame, running its own script.
  Page
}

/// The kind of figure an image path names, if any. A query or fragment is
/// not part of the extension, and case does not matter.
pub fn figure_kind(url: String) -> Option(FigureKind) {
  let path =
    url
    |> string.split("#")
    |> list.first
    |> result.unwrap("")
    |> string.split("?")
    |> list.first
    |> result.unwrap("")
    |> string.lowercase
  case string.ends_with(path, ".svg"), string.ends_with(path, ".json") {
    True, _ -> Some(Drawing)
    _, True -> Some(Chart)
    _, _ ->
      case string.ends_with(path, ".html") || string.ends_with(path, ".htm") {
        True -> Some(Page)
        False -> None
      }
  }
}

/// The images of a cell body whose file the slide needs to read: drawings
/// and charts, as written.
pub fn figures(source: String) -> List(String) {
  images(source)
  |> list.filter(fn(url) {
    case figure_kind(url) {
      Some(Drawing) | Some(Chart) -> True
      _ -> False
    }
  })
}

// Images ------------------------------------------------------------------------

/// The images a cell body draws that are not at a URL with a scheme: paths for
/// the deck's folder, as written, at any depth and in table cells too.
pub fn images(source: String) -> List(String) {
  list.flat_map(top_level(source), fn(block) {
    case block {
      Contained(container:, ..) -> container_images(container)
      Tabular(table:) ->
        [table.head, ..table.rows]
        |> list.flatten
        |> list.flat_map(inline_images)
    }
  })
  |> list.unique
}

fn container_images(c: Container) -> List(String) {
  case c {
    Paragraph(content:, ..) | Heading(content:, ..) -> inline_images(content)
    BlockQuote(items:, ..) | Div(items:, ..) ->
      list.flat_map(items, container_images)
    BulletList(items:, ..) | OrderedList(items:, ..) ->
      list.flat_map(items, list.flat_map(_, container_images))
    _ -> []
  }
}

fn inline_images(content: List(Inline)) -> List(String) {
  list.flat_map(content, fn(i) {
    case i {
      Image(destination: Url(url), ..) ->
        case scheme(string.trim(url)) {
          None -> [string.trim(url)]
          Some(_) -> []
        }
      Emphasis(content)
      | Strong(content)
      | Link(content:, ..)
      | Span(content:, ..)
      | Delete(content)
      | Insert(content)
      | Mark(content)
      | Superscript(content)
      | Subscript(content) -> inline_images(content)
      _ -> []
    }
  })
}

// Top-level blocks and tables ---------------------------------------------------

/// A cell body's top-level blocks. They are jot's, paired with the source of
/// each from `blocks.split`, which is how tables are found and indents kept.
/// Should the two not match up, there are no tables and no indents.
pub fn top_level(source: String) -> List(Block) {
  let content = parse(source).content
  let sources = blocks.split(source)
  case list.length(sources) == list.length(content) {
    False -> list.map(content, Contained(_, []))
    True ->
      list.zip(content, sources)
      |> list.map2(continuation_indents(source), fn(pair, lines) {
        case pair.0, table(pair.1) {
          Paragraph(..), Some(table) -> Tabular(table)
          container, _ -> Contained(container, lines)
        }
      })
  }
}

/// The table in a block's source: a row, then a separator line, then any
/// lines at all as rows, so that a table stays one while a row is typed.
pub fn table(block: String) -> Option(Table) {
  case string.split(block, "\n") |> list.map(string.trim) {
    ["|" <> _ as first, "|" <> _ as second, ..rest] ->
      case separator(second) {
        None -> None
        Some(aligns) ->
          Some(build_table(row(first), aligns, list.map(rest, row)))
      }
    _ -> None
  }
}

/// The source of a row's cells, and whether the row is well made.
type Row {
  Row(cells: List(String), regular: Bool)
}

fn build_table(head: Row, aligns: List(ColumnAlign), rows: List(Row)) -> Table {
  let width =
    list.fold([head, ..rows], list.length(aligns), fn(width, row) {
      int.max(width, list.length(row.cells))
    })
  let regular =
    list.all([head, ..rows], fn(row) {
      row.regular && list.length(row.cells) == list.length(aligns)
    })
  Table(
    columns: pad(aligns, width, AlignDefault),
    head: row_inlines(head, width),
    rows: list.map(rows, row_inlines(_, width)),
    regular:,
  )
}

fn row_inlines(row: Row, width: Int) -> List(List(Inline)) {
  pad(list.map(row.cells, cell_inlines), width, [])
}

fn pad(xs: List(a), width: Int, filler: a) -> List(a) {
  list.append(xs, list.repeat(filler, width - list.length(xs)))
}

/// A cell's inline content. A leading word keeps jot from reading `# x` or
/// `- x` as a block, and is taken off the first text again.
fn cell_inlines(cell: String) -> List(Inline) {
  case parse("a " <> cell).content {
    [Paragraph(content: [Text("a " <> rest), ..others], ..)] ->
      case rest {
        "" -> others
        _ -> [Text(rest), ..others]
      }
    _ if cell == "" -> []
    _ -> [Text(cell)]
  }
}

fn row(line: String) -> Row {
  case line {
    "|" <> rest -> {
      let #(cells, closed) = row_cells(rest)
      Row(cells, closed && separator(line) == None)
    }
    _ -> Row(row_cells(line).0, False)
  }
}

/// The alignments of a separator line such as `|:---|---:|`.
fn separator(line: String) -> Option(List(ColumnAlign)) {
  case line {
    "|" <> rest ->
      case row_cells(rest) {
        #([_, ..] as cells, True) ->
          list.try_map(cells, separator_cell) |> option.from_result
        _ -> None
      }
    _ -> None
  }
}

fn separator_cell(cell: String) -> Result(ColumnAlign, Nil) {
  let #(start, rest) = case cell {
    ":" <> rest -> #(True, rest)
    _ -> #(False, cell)
  }
  let #(end, dashes) = case string.ends_with(rest, ":") {
    True -> #(True, string.drop_end(rest, 1))
    False -> #(False, rest)
  }
  case dashes != "" && string.replace(dashes, "-", "") == "" {
    False -> Error(Nil)
    True ->
      Ok(case start, end {
        False, False -> AlignDefault
        True, False -> AlignStart
        True, True -> AlignCenter
        False, True -> AlignEnd
      })
  }
}

/// A row's text after its opening pipe, split at the pipes that are neither
/// escaped nor in inline code. The cells are trimmed. The flag says whether
/// the row ended in such a pipe.
fn row_cells(text: String) -> #(List(String), Bool) {
  scan_cells(string.to_graphemes(text), [], [], 0)
}

/// `ticks` is the length of the backtick run that opened the code span we are
/// in, or 0 outside code.
fn scan_cells(
  chars: List(String),
  cell: List(String),
  cells: List(String),
  ticks: Int,
) -> #(List(String), Bool) {
  let finish = fn(chars) { string.trim(string.concat(list.reverse(chars))) }
  case chars, ticks {
    [], _ ->
      case finish(cell) {
        "" -> #(list.reverse(cells), ticks == 0 && cells != [])
        last -> #(list.reverse([last, ..cells]), False)
      }
    ["\\", next, ..rest], 0 -> scan_cells(rest, [next, "\\", ..cell], cells, 0)
    ["|", ..rest], 0 -> scan_cells(rest, [], [finish(cell), ..cells], 0)
    ["`", ..], _ -> {
      let run = list.take_while(chars, fn(c) { c == "`" })
      let n = list.length(run)
      let ticks = case ticks {
        0 -> n
        open if open == n -> 0
        open -> open
      }
      scan_cells(list.drop(chars, n), list.append(run, cell), cells, ticks)
    }
    [c, ..rest], _ -> scan_cells(rest, [c, ..cell], cells, ticks)
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
