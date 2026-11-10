//// deck.md: the reader with its reading rules and the canonical printer;
//// layout.json: printing and parsing (02-file-format.md).

import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import junkslides/blocks
import junkslides/codec
import junkslides/deck.{type Cell, type Deck, Cell, Content, Deck, Notes, Slide}
import junkslides/id.{
  type CellTag, type Id, type IdSet, type IdSupply, type SlideTag,
}
import junkslides/layout.{type Layout}
import junkslides/line.{Body, Break, CellMarker, Header, SlideMarker}

pub type ParseError {
  /// Line numbers start at 1.
  ParseError(line: Int, problem: Problem)
}

pub type Problem {
  /// Reading rule 9.
  UnknownVersion(version: Int)
  /// A header line anywhere but the first line.
  MisplacedHeader
  /// Reading rule 8.
  SlideMarkerWithoutBreak
}

// Reading ----------------------------------------------------------------

/// A slide as written, before IDs are assigned.
type RawSlide {
  RawSlide(
    id: Option(Id(SlideTag)),
    unmarked: List(String),
    cells: List(RawCell),
  )
}

type RawCell {
  RawCell(notes: Bool, id: Option(Id(CellTag)), body: List(String))
}

/// Lines are collected in reverse and put in order at the end.
type Reader {
  Reader(slides: List(RawSlide), current: RawSlide, previous: line.Line)
}

/// A parse error as a sentence for the user.
pub fn describe(error: ParseError) -> String {
  let problem = case error.problem {
    UnknownVersion(version) ->
      "unknown format version " <> int.to_string(version)
    MisplacedHeader -> "the header must be the first line"
    SlideMarkerWithoutBreak -> "a slide marker must follow a break"
  }
  "deck.md line " <> int.to_string(error.line) <> ": " <> problem <> "."
}

pub fn parse(
  text: String,
  supply: IdSupply,
) -> Result(#(Deck, IdSupply), ParseError) {
  let numbered = line.lines(text) |> list.index_map(fn(l, i) { #(i + 1, l) })
  let start = Reader([], RawSlide(None, [], []), Body)
  case list.try_fold(numbered, start, read_line) {
    Error(error) -> Error(error)
    Ok(reader) -> {
      let raw =
        [reader.current, ..reader.slides]
        |> list.reverse
        |> list.map(in_order)
        |> drop_empty_preamble
      Ok(assign_ids(raw, supply))
    }
  }
}

fn read_line(
  reader: Reader,
  numbered: #(Int, String),
) -> Result(Reader, ParseError) {
  let #(number, text) = numbered
  let kind = line.classify(text)
  let reader = case kind, reader.previous, number {
    Header(1), _, 1 -> Ok(reader)
    Header(version), _, 1 -> Error(ParseError(number, UnknownVersion(version)))
    Header(_), _, _ -> Error(ParseError(number, MisplacedHeader))
    Break, _, _ ->
      Ok(
        Reader(
          ..reader,
          slides: [reader.current, ..reader.slides],
          current: RawSlide(None, [], []),
        ),
      )
    SlideMarker(id), Break, _ ->
      Ok(Reader(..reader, current: RawSlide(..reader.current, id: Some(id))))
    SlideMarker(_), _, _ -> Error(ParseError(number, SlideMarkerWithoutBreak))
    CellMarker(notes:, id:), _, _ -> {
      let cell = RawCell(notes:, id:, body: [])
      let current = reader.current
      Ok(
        Reader(
          ..reader,
          current: RawSlide(..current, cells: [cell, ..current.cells]),
        ),
      )
    }
    Body, _, _ -> Ok(Reader(..reader, current: add_body(reader.current, text)))
  }
  case reader {
    Ok(reader) -> Ok(Reader(..reader, previous: kind))
    Error(error) -> Error(error)
  }
}

fn add_body(slide: RawSlide, text: String) -> RawSlide {
  case slide.cells {
    [] -> RawSlide(..slide, unmarked: [text, ..slide.unmarked])
    [cell, ..rest] ->
      RawSlide(..slide, cells: [
        RawCell(..cell, body: [text, ..cell.body]),
        ..rest
      ])
  }
}

fn in_order(slide: RawSlide) -> RawSlide {
  RawSlide(
    ..slide,
    unmarked: list.reverse(slide.unmarked),
    cells: list.reverse(slide.cells)
      |> list.map(fn(cell) { RawCell(..cell, body: list.reverse(cell.body)) }),
  )
}

/// The text before the first break becomes a slide only when it has content
/// (reading rule 2). An empty file is a deck with one empty slide.
fn drop_empty_preamble(slides: List(RawSlide)) -> List(RawSlide) {
  case slides {
    [preamble, ..rest] ->
      case preamble.cells == [] && list.all(preamble.unmarked, line.is_blank) {
        True ->
          case rest {
            [] -> [RawSlide(None, [], [])]
            _ -> rest
          }
        False -> slides
      }
    [] -> [RawSlide(None, [], [])]
  }
}

/// Fresh IDs avoid every ID written in the file, so that a later marker
/// keeps its ID even when an earlier one was missing.
type Ids {
  Ids(written: IdSet, seen: IdSet, supply: IdSupply)
}

fn assign_ids(raw: List(RawSlide), supply: IdSupply) -> #(Deck, IdSupply) {
  let written =
    list.fold(raw, id.empty_set(), fn(set, slide) {
      let set = case slide.id {
        Some(slide) -> id.insert(set, slide)
        None -> set
      }
      list.fold(slide.cells, set, fn(set, cell) {
        case cell.id {
          Some(cell) -> id.insert(set, cell)
          None -> set
        }
      })
    })
  let #(ids, slides) =
    list.map_fold(raw, Ids(written, id.empty_set(), supply), assign_slide)
  #(Deck(slides), ids.supply)
}

fn assign_slide(ids: Ids, raw: RawSlide) -> #(Ids, deck.Slide) {
  let #(ids, slide_id) = keep_or_fresh(ids, raw.id)
  let unmarked =
    raw.unmarked
    |> string.join("\n")
    |> blocks.split
    |> list.map(fn(block) { RawCell(False, None, [block]) })
  let #(ids, cells) =
    list.map_fold(list.append(unmarked, raw.cells), ids, assign_cell)
  #(ids, Slide(slide_id, cells))
}

fn assign_cell(ids: Ids, raw: RawCell) -> #(Ids, Cell) {
  let #(ids, cell_id) = keep_or_fresh(ids, raw.id)
  let kind = case raw.notes {
    True -> Notes
    False -> Content
  }
  let source = raw.body |> string.join("\n") |> line.trim_blank_lines
  #(ids, Cell(cell_id, kind, source))
}

/// Reading rules 3, 4 and 7: a missing ID, or one seen before, is replaced
/// by a fresh one.
fn keep_or_fresh(ids: Ids, written: Option(Id(tag))) -> #(Ids, Id(tag)) {
  case written {
    Some(kept) ->
      case id.contains(ids.seen, kept) {
        False -> #(Ids(..ids, seen: id.insert(ids.seen, kept)), kept)
        True -> fresh(ids)
      }
    None -> fresh(ids)
  }
}

fn fresh(ids: Ids) -> #(Ids, Id(tag)) {
  let taken = id.union(ids.written, ids.seen)
  let #(new, supply) = id.fresh(ids.supply, taken)
  #(Ids(..ids, seen: id.insert(ids.seen, new), supply:), new)
}

// Printing ---------------------------------------------------------------

/// The canonical printer: the same deck always prints to the same bytes.
pub fn print(deck: Deck) -> String {
  let slides =
    list.flat_map(deck.slides, fn(slide) {
      let marker = "---\n" <> line.slide_line(slide.id)
      [marker, ..list.map(slide.cells, print_cell)]
    })
  string.join([line.header_line(), ..slides], "\n\n") <> "\n"
}

fn print_cell(cell: Cell) -> String {
  let marker = line.cell_line(cell.kind == Notes, cell.id)
  case cell.source {
    "" -> marker
    source -> marker <> "\n" <> source
  }
}

// layout.json ------------------------------------------------------------

/// layout.json as written by junkslides: two-space indentation, records sorted by
/// ID, a final newline.
pub fn print_layout(layout: Layout) -> String {
  codec.pretty(codec.layout_value(layout))
}

/// Parses and validates layout.json. Any problem keeps the whole file out;
/// the caller keeps its current layout (06-runtime.md).
pub fn parse_layout(text: String) -> Result(Layout, json.DecodeError) {
  json.parse(text, codec.layout_decoder())
}
