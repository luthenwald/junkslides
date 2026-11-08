//// Operations on the deck, the effects they report, and edit normalisation
//// (03-data-model.md, Operations, Effects and Identity rules).

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import junkslides/deck.{
  type Cell, type Deck, type Kind, type Position, type Slide, Cell, Content,
  Deck, Notes, Position, Slide,
}
import junkslides/id.{type CellTag, type Id, type IdSupply, type SlideTag}
import junkslides/line

pub type Op {
  EditText(cell: Id(CellTag), source: String)
  Insert(at: Position, kind: Kind)
  Delete(cell: Id(CellTag))
  Split(cell: Id(CellTag), at: Int)
  MergeWithNext(cell: Id(CellTag))
  Move(cell: Id(CellTag), to: Position)
  Duplicate(cell: Id(CellTag))
  CycleKind(cell: Id(CellTag))
  Paste(cell: Cell, at: Position)
  InsertBreak(at: Position)
  RemoveBreak(slide: Id(SlideTag))
  MoveSlide(slide: Id(SlideTag), to_index: Int)
  DeleteSlide(slide: Id(SlideTag))
}

/// Only changes of identity. A cell that keeps its ID produces no effect,
/// even if it moved or its text changed.
pub type Effect {
  Fresh(cell: Id(CellTag), inherit_style: Option(Id(CellTag)))
  Retired(cell: Id(CellTag))
  Revived(cell: Id(CellTag))
  SlideFresh(slide: Id(SlideTag))
  SlideRetired(slide: Id(SlideTag))
}

pub type OpError {
  UnknownCell(cell: Id(CellTag))
  UnknownSlide(slide: Id(SlideTag))
  PositionOutOfRange
  NoNextCell
  RemoveFirstBreak
  DeleteOnlySlide
  AreaOffSlide
  /// The source of an `EditText` or `Paste` breaks deck invariant 3 or 4,
  /// or a `Split` would cut a line into a structural one (` ---` cut after
  /// the space).
  Unnormalised
}

type Applied =
  Result(#(Deck, List(Effect), IdSupply), OpError)

/// Applies one op. Errors never change the deck.
pub fn apply(deck: Deck, op: Op, supply: IdSupply) -> Applied {
  case op {
    EditText(cell:, source:) -> edit_text(deck, cell, source, supply)
    Insert(at:, kind:) -> {
      let #(new, supply) = id.fresh(supply, deck.ids(deck))
      use deck <- then(insert_cell(deck, at, Cell(new, kind, "")))
      Ok(#(deck, [Fresh(new, None)], supply))
    }
    Delete(cell:) -> {
      use #(deck, _) <- then(remove_cell(deck, cell))
      Ok(#(deck, [Retired(cell)], supply))
    }
    Split(cell:, at:) -> split(deck, cell, at, supply)
    MergeWithNext(cell:) -> merge(deck, cell, supply)
    Move(cell:, to:) -> {
      use #(deck, moved) <- then(remove_cell(deck, cell))
      use deck <- then(insert_cell(deck, to, moved))
      Ok(#(deck, [], supply))
    }
    Duplicate(cell:) -> {
      use location <- then(locate(deck, cell))
      let #(copy, supply) = id.fresh(supply, deck.ids(deck))
      let at = Position(location.slide.id, location.index + 1)
      use deck <- then(insert_cell(deck, at, Cell(..location.cell, id: copy)))
      Ok(#(deck, [Fresh(copy, Some(cell))], supply))
    }
    CycleKind(cell:) -> {
      use location <- then(locate(deck, cell))
      let kind = case location.cell.kind {
        Content -> Notes
        Notes -> Content
      }
      let deck = replace_cell(deck, Cell(..location.cell, kind:))
      Ok(#(deck, [], supply))
    }
    Paste(cell:, at:) -> paste(deck, cell, at, supply)
    InsertBreak(at:) -> insert_break(deck, at, supply)
    RemoveBreak(slide:) -> remove_break(deck, slide, supply)
    MoveSlide(slide:, to_index:) -> {
      use moved <- then(find_slide(deck, slide))
      let rest = list.filter(deck.slides, fn(s) { s.id != slide })
      case to_index >= 0 && to_index <= list.length(rest) {
        True -> Ok(#(Deck(insert_at(rest, to_index, moved)), [], supply))
        False -> Error(PositionOutOfRange)
      }
    }
    DeleteSlide(slide:) -> {
      use removed <- then(find_slide(deck, slide))
      case deck.slides {
        [_] -> Error(DeleteOnlySlide)
        _ -> {
          let rest = list.filter(deck.slides, fn(s) { s.id != slide })
          let effects = [
            SlideRetired(slide),
            ..list.map(removed.cells, fn(c) { Retired(c.id) })
          ]
          Ok(#(Deck(rest), effects, supply))
        }
      }
    }
  }
}

/// Applies ops in order, all or nothing. Effects are concatenated.
pub fn apply_all(deck: Deck, ops: List(Op), supply: IdSupply) -> Applied {
  list.try_fold(ops, #(deck, [], supply), fn(acc, op) {
    let #(deck, effects, supply) = acc
    use #(deck, more, supply) <- then(apply(deck, op, supply))
    Ok(#(deck, list.append(effects, more), supply))
  })
}

fn edit_text(
  deck: Deck,
  cell: Id(CellTag),
  source: String,
  supply: IdSupply,
) -> Applied {
  use location <- then(locate(deck, cell))
  case deck.valid_source(source) {
    True -> {
      let deck = replace_cell(deck, Cell(..location.cell, source:))
      Ok(#(deck, [], supply))
    }
    False -> Error(Unnormalised)
  }
}

fn split(deck: Deck, cell: Id(CellTag), at: Int, supply: IdSupply) -> Applied {
  use location <- then(locate(deck, cell))
  let source = location.cell.source
  case at >= 0 && at <= string.length(source) {
    False -> Error(PositionOutOfRange)
    True -> {
      let first = string.slice(source, 0, at) |> line.trim_blank_lines
      let second = string.drop_start(source, at) |> line.trim_blank_lines
      use <- guard(
        deck.valid_source(first) && deck.valid_source(second),
        Unnormalised,
      )
      let #(new, supply) = id.fresh(supply, deck.ids(deck))
      let deck = replace_cell(deck, Cell(..location.cell, source: first))
      let at = Position(location.slide.id, location.index + 1)
      use deck <- then(insert_cell(
        deck,
        at,
        Cell(new, location.cell.kind, second),
      ))
      Ok(#(deck, [Fresh(new, Some(cell))], supply))
    }
  }
}

fn merge(deck: Deck, cell: Id(CellTag), supply: IdSupply) -> Applied {
  use location <- then(locate(deck, cell))
  case list.drop(location.slide.cells, location.index + 1) {
    [] -> Error(NoNextCell)
    [next, ..] -> {
      let source = case location.cell.source, next.source {
        "", other | other, "" -> other
        first, second -> first <> "\n\n" <> second
      }
      let deck = replace_cell(deck, Cell(..location.cell, source:))
      use #(deck, _) <- then(remove_cell(deck, next.id))
      Ok(#(deck, [Retired(next.id)], supply))
    }
  }
}

/// The paste rule: the ID is reused if and only if it is not live.
fn paste(deck: Deck, cell: Cell, at: Position, supply: IdSupply) -> Applied {
  case deck.valid_source(cell.source) {
    False -> Error(Unnormalised)
    True -> {
      let live = deck.ids(deck)
      case id.contains(live, cell.id) {
        True -> {
          let #(new, supply) = id.fresh(supply, live)
          use deck <- then(insert_cell(deck, at, Cell(..cell, id: new)))
          Ok(#(deck, [Fresh(new, Some(cell.id))], supply))
        }
        False -> {
          use deck <- then(insert_cell(deck, at, cell))
          Ok(#(deck, [Revived(cell.id)], supply))
        }
      }
    }
  }
}

fn insert_break(deck: Deck, at: Position, supply: IdSupply) -> Applied {
  use slide <- then(find_slide(deck, at.slide))
  case at.index >= 0 && at.index <= list.length(slide.cells) {
    False -> Error(PositionOutOfRange)
    True -> {
      let #(new, supply) = id.fresh(supply, deck.ids(deck))
      let #(before, after) = list.split(slide.cells, at.index)
      let slides =
        list.flat_map(deck.slides, fn(s) {
          case s.id == slide.id {
            True -> [Slide(s.id, before), Slide(new, after)]
            False -> [s]
          }
        })
      Ok(#(Deck(slides), [SlideFresh(new)], supply))
    }
  }
}

fn remove_break(deck: Deck, slide: Id(SlideTag), supply: IdSupply) -> Applied {
  use _ <- then(find_slide(deck, slide))
  case deck.slides {
    [first, ..] if first.id == slide -> Error(RemoveFirstBreak)
    _ -> {
      let slides =
        list.fold(deck.slides, [], fn(acc: List(Slide), s) {
          case s.id == slide, acc {
            True, [previous, ..rest] -> [
              Slide(previous.id, list.append(previous.cells, s.cells)),
              ..rest
            ]
            _, _ -> [s, ..acc]
          }
        })
      Ok(#(Deck(list.reverse(slides)), [SlideRetired(slide)], supply))
    }
  }
}

// Normalising edits --------------------------------------------------------

pub type EditProblem {
  /// A line that is exactly a marker or a header. Lines start at 1.
  MarkerLine(line: Int)
  EditUnknownCell
}

/// Turns the text typed into a cell into ops. A line that is exactly `---`
/// starts a new slide there; a marker line is rejected. Unchanged text gives
/// no ops.
///
/// The deck is needed to address the slide of the cell. For text with `k`
/// breaks, the parts are `p0` to `pk`. The cell first gets all parts joined,
/// then splits are made from the last part backwards, so that the cell being
/// split keeps its ID throughout and each split leaves the new cell right
/// after it, where `InsertBreak` moves it (and the cells after it) to a new
/// slide.
pub fn normalize_edit(
  deck: Deck,
  cell: Id(CellTag),
  new_source: String,
) -> Result(List(Op), EditProblem) {
  case deck.find_cell(deck, cell) {
    Error(Nil) -> Error(EditUnknownCell)
    Ok(location) -> {
      let lines = line.lines(new_source)
      let marker =
        list.index_map(lines, fn(l, i) { #(i + 1, line.classify(l)) })
        |> list.find(fn(pair) { pair.1 != line.Body && pair.1 != line.Break })
      case marker {
        Ok(#(number, _)) -> Error(MarkerLine(number))
        Error(Nil) -> Ok(edit_ops(location, lines))
      }
    }
  }
}

fn edit_ops(location: deck.Location, lines: List(String)) -> List(Op) {
  let cell = location.cell.id
  let parts =
    split_on_breaks(lines, [], [])
    |> list.map(fn(part) { string.join(part, "\n") |> line.trim_blank_lines })
  let prefixes =
    list.index_map(parts, fn(_, i) {
      list.take(parts, i + 1) |> string.join("\n\n") |> line.trim_blank_lines
    })
  case prefixes {
    [only] if only == location.cell.source -> []
    _ -> {
      let assert Ok(whole) = list.last(prefixes)
      let next = Position(location.slide.id, location.index + 1)
      let breaks =
        list.reverse(prefixes)
        |> list.drop(1)
        |> list.flat_map(fn(prefix) {
          [Split(cell, string.length(prefix)), InsertBreak(next)]
        })
      [EditText(cell, whole), ..breaks]
    }
  }
}

/// Parts in order, each a list of lines in order.
fn split_on_breaks(
  lines: List(String),
  current: List(String),
  done: List(List(String)),
) -> List(List(String)) {
  case lines {
    [] -> list.reverse([list.reverse(current), ..done])
    ["---", ..rest] ->
      split_on_breaks(rest, [], [list.reverse(current), ..done])
    [l, ..rest] -> split_on_breaks(rest, [l, ..current], done)
  }
}

// Helpers ------------------------------------------------------------------

fn then(result: Result(a, OpError), next: fn(a) -> Result(b, OpError)) {
  case result {
    Ok(value) -> next(value)
    Error(error) -> Error(error)
  }
}

fn guard(ok: Bool, error: OpError, next: fn() -> Applied) -> Applied {
  case ok {
    True -> next()
    False -> Error(error)
  }
}

fn locate(deck: Deck, cell: Id(CellTag)) -> Result(deck.Location, OpError) {
  case deck.find_cell(deck, cell) {
    Ok(location) -> Ok(location)
    Error(Nil) -> Error(UnknownCell(cell))
  }
}

fn find_slide(deck: Deck, slide: Id(SlideTag)) -> Result(Slide, OpError) {
  case deck.find_slide(deck, slide) {
    Ok(found) -> Ok(found)
    Error(Nil) -> Error(UnknownSlide(slide))
  }
}

fn replace_cell(deck: Deck, cell: Cell) -> Deck {
  map_slides(deck, fn(slide) {
    Slide(
      ..slide,
      cells: list.map(slide.cells, fn(c) {
        case c.id == cell.id {
          True -> cell
          False -> c
        }
      }),
    )
  })
}

fn remove_cell(
  deck: Deck,
  cell: Id(CellTag),
) -> Result(#(Deck, Cell), OpError) {
  use location <- then(locate(deck, cell))
  let deck =
    map_slides(deck, fn(slide) {
      Slide(..slide, cells: list.filter(slide.cells, fn(c) { c.id != cell }))
    })
  Ok(#(deck, location.cell))
}

fn insert_cell(deck: Deck, at: Position, cell: Cell) -> Result(Deck, OpError) {
  use slide <- then(find_slide(deck, at.slide))
  case at.index >= 0 && at.index <= list.length(slide.cells) {
    False -> Error(PositionOutOfRange)
    True ->
      Ok(
        map_slides(deck, fn(s) {
          case s.id == at.slide {
            True -> Slide(..s, cells: insert_at(s.cells, at.index, cell))
            False -> s
          }
        }),
      )
  }
}

fn map_slides(deck: Deck, f: fn(Slide) -> Slide) -> Deck {
  Deck(list.map(deck.slides, f))
}

fn insert_at(items: List(a), index: Int, item: a) -> List(a) {
  let #(before, after) = list.split(items, int.max(index, 0))
  list.flatten([before, [item], after])
}
