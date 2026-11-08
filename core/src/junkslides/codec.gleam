//// JSON for decks, ops, layouts and layout ops, shared by layout.json and
//// the protocol.
////
//// Encoders build a small `Value` tree rather than `gleam/json` values, so
//// that layout.json can be pretty-printed with stable formatting. `to_json`
//// turns a `Value` into `gleam/json` for compact output.

import gleam/dict.{type Dict}
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import junkslides/deck.{
  type Cell, type Deck, type Kind, type Position, Cell, Content, Deck, Notes,
  Position, Slide,
}
import junkslides/id.{type Id}
import junkslides/layout.{
  type Align, type Area, type CellRecord, type Layout, type LayoutOp,
  type Orphan, Area, CellOrphan, CellRecord, Layout, SlideOrphan, SlideRecord,
}
import junkslides/op.{type Op}

// Values -------------------------------------------------------------------

pub type Value {
  Obj(List(#(String, Value)))
  Arr(List(Value))
  Str(String)
  Num(Int)
  Bool(Bool)
  Null
}

pub fn to_json(value: Value) -> Json {
  case value {
    Obj(fields) -> json.object(list.map(fields, fn(f) { #(f.0, to_json(f.1)) }))
    Arr(items) -> json.preprocessed_array(list.map(items, to_json))
    Str(text) -> json.string(text)
    Num(n) -> json.int(n)
    Bool(b) -> json.bool(b)
    Null -> json.null()
  }
}

pub fn to_string(value: Value) -> String {
  value |> to_json |> json.to_string
}

/// Two-space indentation. Objects and arrays from depth 3 on are written on
/// one line, which keeps grid areas and orphan records compact.
pub fn pretty(value: Value) -> String {
  pretty_at(value, 0) <> "\n"
}

fn pretty_at(value: Value, depth: Int) -> String {
  let inner = string.repeat("  ", depth + 1)
  let outer = string.repeat("  ", depth)
  case value {
    Obj([]) -> "{}"
    Arr([]) -> "[]"
    Obj(fields) if depth >= 3 ->
      "{ "
      <> list.map(fields, fn(f) {
        quote(f.0) <> ": " <> pretty_at(f.1, depth + 1)
      })
      |> string.join(", ")
      <> " }"
    Arr(items) if depth >= 3 ->
      "["
      <> list.map(items, pretty_at(_, depth + 1)) |> string.join(", ")
      <> "]"
    Obj(fields) ->
      "{\n"
      <> list.map(fields, fn(f) {
        inner <> quote(f.0) <> ": " <> pretty_at(f.1, depth + 1)
      })
      |> string.join(",\n")
      <> "\n"
      <> outer
      <> "}"
    Arr(items) ->
      "[\n"
      <> list.map(items, fn(item) { inner <> pretty_at(item, depth + 1) })
      |> string.join(",\n")
      <> "\n"
      <> outer
      <> "]"
    Str(_) | Num(_) | Bool(_) | Null -> to_string(value)
  }
}

fn quote(text: String) -> String {
  json.string(text) |> json.to_string
}

fn optional(fields: List(#(String, Option(Value)))) -> Value {
  Obj(
    list.filter_map(fields, fn(f) {
      case f.1 {
        Some(value) -> Ok(#(f.0, value))
        None -> Error(Nil)
      }
    }),
  )
}

pub fn id_value(id: Id(tag)) -> Value {
  Str(id.to_string(id))
}

/// Fails with `expected`. The fallback decoder only supplies a placeholder
/// value, for types (holding IDs) that have none to hand.
fn unknown(expected: String, fallback: Decoder(a)) -> Decoder(a) {
  decode.failure(Nil, expected) |> decode.then(fn(_) { fallback })
}

fn tagged(tag: String, fields: List(#(String, Value))) -> Value {
  Obj([#("op", Str(tag)), ..fields])
}

// Deck ---------------------------------------------------------------------

pub fn kind_value(kind: Kind) -> Value {
  case kind {
    Content -> Str("content")
    Notes -> Str("notes")
  }
}

pub fn cell_value(cell: Cell) -> Value {
  Obj([
    #("id", id_value(cell.id)),
    #("kind", kind_value(cell.kind)),
    #("source", Str(cell.source)),
  ])
}

pub fn deck_value(deck: Deck) -> Value {
  Arr(
    list.map(deck.slides, fn(slide) {
      Obj([
        #("id", id_value(slide.id)),
        #("cells", Arr(list.map(slide.cells, cell_value))),
      ])
    }),
  )
}

pub fn position_value(position: Position) -> Value {
  Obj([#("slide", id_value(position.slide)), #("index", Num(position.index))])
}

pub fn kind_decoder() -> Decoder(Kind) {
  use text <- decode.then(decode.string)
  case text {
    "content" -> decode.success(Content)
    "notes" -> decode.success(Notes)
    _ -> decode.failure(Content, "Kind")
  }
}

pub fn cell_decoder() -> Decoder(Cell) {
  use cell_id <- decode.field("id", id.decoder())
  use kind <- decode.field("kind", kind_decoder())
  use source <- decode.field("source", decode.string)
  decode.success(Cell(cell_id, kind, source))
}

pub fn deck_decoder() -> Decoder(Deck) {
  let slide = {
    use slide_id <- decode.field("id", id.decoder())
    use cells <- decode.field("cells", decode.list(cell_decoder()))
    decode.success(Slide(slide_id, cells))
  }
  decode.list(slide) |> decode.map(Deck)
}

pub fn position_decoder() -> Decoder(Position) {
  use slide <- decode.field("slide", id.decoder())
  use index <- decode.field("index", decode.int)
  decode.success(Position(slide, index))
}

// Ops ----------------------------------------------------------------------

pub fn op_value(op: Op) -> Value {
  case op {
    op.EditText(cell:, source:) ->
      tagged("edit_text", [#("cell", id_value(cell)), #("source", Str(source))])
    op.Insert(at:, kind:) ->
      tagged("insert", [
        #("at", position_value(at)),
        #("kind", kind_value(kind)),
      ])
    op.Delete(cell:) -> tagged("delete", [#("cell", id_value(cell))])
    op.Split(cell:, at:) ->
      tagged("split", [#("cell", id_value(cell)), #("at", Num(at))])
    op.MergeWithNext(cell:) ->
      tagged("merge_with_next", [#("cell", id_value(cell))])
    op.Move(cell:, to:) ->
      tagged("move", [#("cell", id_value(cell)), #("to", position_value(to))])
    op.Duplicate(cell:) -> tagged("duplicate", [#("cell", id_value(cell))])
    op.CycleKind(cell:) -> tagged("cycle_kind", [#("cell", id_value(cell))])
    op.Paste(cell:, at:) ->
      tagged("paste", [#("cell", cell_value(cell)), #("at", position_value(at))])
    op.InsertBreak(at:) -> tagged("insert_break", [#("at", position_value(at))])
    op.RemoveBreak(slide:) ->
      tagged("remove_break", [#("slide", id_value(slide))])
    op.MoveSlide(slide:, to_index:) ->
      tagged("move_slide", [
        #("slide", id_value(slide)),
        #("to_index", Num(to_index)),
      ])
    op.DeleteSlide(slide:) ->
      tagged("delete_slide", [#("slide", id_value(slide))])
  }
}

pub fn op_decoder() -> Decoder(Op) {
  let cell = decode.field("cell", id.decoder(), _)
  let slide = decode.field("slide", id.decoder(), _)
  let at = decode.field("at", position_decoder(), _)
  use tag <- decode.field("op", decode.string)
  case tag {
    "edit_text" -> {
      use c <- cell
      use source <- decode.field("source", decode.string)
      decode.success(op.EditText(c, source))
    }
    "insert" -> {
      use position <- at
      use kind <- decode.field("kind", kind_decoder())
      decode.success(op.Insert(position, kind))
    }
    "delete" -> cell(fn(c) { decode.success(op.Delete(c)) })
    "split" -> {
      use c <- cell
      use index <- decode.field("at", decode.int)
      decode.success(op.Split(c, index))
    }
    "merge_with_next" -> cell(fn(c) { decode.success(op.MergeWithNext(c)) })
    "move" -> {
      use c <- cell
      use to <- decode.field("to", position_decoder())
      decode.success(op.Move(c, to))
    }
    "duplicate" -> cell(fn(c) { decode.success(op.Duplicate(c)) })
    "cycle_kind" -> cell(fn(c) { decode.success(op.CycleKind(c)) })
    "paste" -> {
      use c <- decode.field("cell", cell_decoder())
      use position <- at
      decode.success(op.Paste(c, position))
    }
    "insert_break" ->
      at(fn(position) { decode.success(op.InsertBreak(position)) })
    "remove_break" -> slide(fn(s) { decode.success(op.RemoveBreak(s)) })
    "move_slide" -> {
      use s <- slide
      use index <- decode.field("to_index", decode.int)
      decode.success(op.MoveSlide(s, index))
    }
    "delete_slide" -> slide(fn(s) { decode.success(op.DeleteSlide(s)) })
    _ -> unknown("Op", cell(fn(c) { decode.success(op.Delete(c)) }))
  }
}

// Layout -------------------------------------------------------------------

pub fn area_value(area: Area) -> Value {
  Obj([
    #("x", Num(area.x)),
    #("y", Num(area.y)),
    #("w", Num(area.w)),
    #("h", Num(area.h)),
  ])
}

pub fn align_value(align: Align) -> Value {
  case align {
    layout.Start -> Str("start")
    layout.Center -> Str("center")
    layout.End -> Str("end")
  }
}

pub fn record_value(record: CellRecord) -> Value {
  optional([
    #("place", option.map(record.place, area_value)),
    #("variant", option.map(record.variant, Str)),
    #("align", option.map(record.align, align_value)),
  ])
}

fn timestamp_value(time: Timestamp) -> Value {
  Str(timestamp.to_rfc3339(time, duration.seconds(0)))
}

fn orphan_value(orphan: Orphan) -> Value {
  case orphan {
    CellOrphan(id:, record:, retired_at:) ->
      Obj([
        #("kind", Str("cell")),
        #("id", id_value(id)),
        #("record", record_value(record)),
        #("retired_at", timestamp_value(retired_at)),
      ])
    SlideOrphan(id:, retired_at:, ..) ->
      Obj([
        #("kind", Str("slide")),
        #("id", id_value(id)),
        #("record", Obj([])),
        #("retired_at", timestamp_value(retired_at)),
      ])
  }
}

/// The layout.json document. Records are sorted by ID so diffs stay small.
pub fn layout_value(layout: Layout) -> Value {
  Obj([
    #("version", Num(2)),
    #("cells", sorted(layout.cells, record_value)),
    #("slides", sorted(layout.slides, fn(_) { Obj([]) })),
    #("orphans", Arr(list.map(layout.orphans, orphan_value))),
  ])
}

fn sorted(records: Dict(Id(tag), a), value: fn(a) -> Value) -> Value {
  dict.to_list(records)
  |> list.sort(fn(a, b) { id.compare(a.0, b.0) })
  |> list.map(fn(pair) { #(id.to_string(pair.0), value(pair.1)) })
  |> Obj
}

/// An area in design pixels, as layout.json version 2 and the protocol
/// write it.
pub fn area_decoder() -> Decoder(Area) {
  use x <- decode.field("x", decode.int)
  use y <- decode.field("y", decode.int)
  use w <- decode.field("w", decode.int)
  use h <- decode.field("h", decode.int)
  checked_area(Area(x, y, w, h))
}

/// The grid units of layout.json version 1: 60 pixels each.
fn area_v1_decoder() -> Decoder(Area) {
  use col <- decode.field("col", decode.int)
  use row <- decode.field("row", decode.int)
  use w <- decode.field("w", decode.int)
  use h <- decode.field("h", decode.int)
  checked_area(Area(col * 60, row * 60, w * 60, h * 60))
}

fn checked_area(area: Area) -> Decoder(Area) {
  case layout.valid_area(area) {
    True -> decode.success(area)
    False -> decode.failure(area, "Area on the slide")
  }
}

pub fn align_decoder() -> Decoder(Align) {
  use text <- decode.then(decode.string)
  case text {
    "start" -> decode.success(layout.Start)
    "center" -> decode.success(layout.Center)
    "end" -> decode.success(layout.End)
    _ -> decode.failure(layout.Start, "Align")
  }
}

pub fn record_decoder() -> Decoder(CellRecord) {
  record_decoder_with(area_decoder())
}

fn record_decoder_with(area: Decoder(Area)) -> Decoder(CellRecord) {
  use place <- decode.optional_field("place", None, decode.map(area, Some))
  use variant <- decode.optional_field(
    "variant",
    None,
    decode.map(decode.string, Some),
  )
  use align <- decode.optional_field(
    "align",
    None,
    decode.map(align_decoder(), Some),
  )
  decode.success(CellRecord(place, variant, align))
}

fn timestamp_decoder() -> Decoder(Timestamp) {
  use text <- decode.then(decode.string)
  case timestamp.parse_rfc3339(text) {
    Ok(time) -> decode.success(time)
    Error(Nil) -> decode.failure(timestamp.from_unix_seconds(0), "Timestamp")
  }
}

fn orphan_decoder(record_decoder: Decoder(CellRecord)) -> Decoder(Orphan) {
  use kind <- decode.field("kind", decode.string)
  use retired_at <- decode.field("retired_at", timestamp_decoder())
  case kind {
    "cell" -> {
      use cell <- decode.field("id", id.decoder())
      use record <- decode.field("record", record_decoder)
      decode.success(CellOrphan(cell, record, retired_at))
    }
    "slide" -> {
      use slide <- decode.field("id", id.decoder())
      decode.success(SlideOrphan(slide, SlideRecord, retired_at))
    }
    _ ->
      unknown(
        "Orphan",
        decode.field("id", id.decoder(), fn(slide) {
          decode.success(SlideOrphan(slide, SlideRecord, retired_at))
        }),
      )
  }
}

/// The layout.json document. Version 2 is written; version 1, in grid units
/// of 60 pixels, is still read.
pub fn layout_decoder() -> Decoder(Layout) {
  use version <- decode.field("version", decode.int)
  let records = case version {
    1 -> Ok(record_decoder_with(area_v1_decoder()))
    2 -> Ok(record_decoder())
    _ -> Error(Nil)
  }
  case records {
    Ok(record_decoder) -> {
      use cells <- decode.field(
        "cells",
        decode.dict(id.decoder(), record_decoder),
      )
      use slides <- decode.optional_field(
        "slides",
        dict.new(),
        decode.dict(id.decoder(), decode.success(SlideRecord)),
      )
      use orphans <- decode.optional_field(
        "orphans",
        [],
        decode.list(orphan_decoder(record_decoder)),
      )
      decode.success(Layout(cells, slides, orphans))
    }
    Error(Nil) ->
      decode.failure(
        layout.empty(),
        "layout.json version 1 or 2, got " <> int.to_string(version),
      )
  }
}

pub fn layout_op_value(op: LayoutOp) -> Value {
  case op {
    layout.Place(cell:, area:) ->
      tagged("place", [#("cell", id_value(cell)), #("area", area_value(area))])
    layout.Unplace(cell:) -> tagged("unplace", [#("cell", id_value(cell))])
    layout.SetVariant(cell:, variant:) ->
      tagged("set_variant", [
        #("cell", id_value(cell)),
        #("variant", option.map(variant, Str) |> option.unwrap(Null)),
      ])
    layout.SetAlign(cell:, align:) ->
      tagged("set_align", [
        #("cell", id_value(cell)),
        #("align", option.map(align, align_value) |> option.unwrap(Null)),
      ])
    layout.PurgeOrphans -> tagged("purge_orphans", [])
  }
}

pub fn layout_op_decoder() -> Decoder(LayoutOp) {
  let cell = decode.field("cell", id.decoder(), _)
  use tag <- decode.field("op", decode.string)
  case tag {
    "place" -> {
      use c <- cell
      use area <- decode.field("area", area_decoder())
      decode.success(layout.Place(c, area))
    }
    "unplace" -> cell(fn(c) { decode.success(layout.Unplace(c)) })
    "set_variant" -> {
      use c <- cell
      use variant <- decode.field("variant", decode.optional(decode.string))
      decode.success(layout.SetVariant(c, variant))
    }
    "set_align" -> {
      use c <- cell
      use align <- decode.field("align", decode.optional(align_decoder()))
      decode.success(layout.SetAlign(c, align))
    }
    "purge_orphans" -> decode.success(layout.PurgeOrphans)
    _ -> decode.failure(layout.PurgeOrphans, "LayoutOp")
  }
}
