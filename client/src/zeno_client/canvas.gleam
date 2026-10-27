//// Canvas arithmetic (04-layout.md, Placing and moving): grid areas from
//// drawn boxes, moves, resizes and nudges clamped to the 32x18 grid, and
//// the cycles of variant and alignment. Pure, so it is unit tested.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import zeno/deck.{type Deck}
import zeno/id.{type CellTag, type Id}
import zeno/layout.{type Align, type Area, type Layout, Area}
import zeno_client/nav.{type Selection, OnCell}

/// One grid unit in design pixels.
pub const unit = 60

/// A drawn cell's box in design pixels, relative to the slide.
pub type Box {
  Box(left: Int, top: Int, width: Int, height: Int)
}

/// The grid area a drawn box covers, its size rounded up to whole units.
pub fn area_of_box(box: Box) -> Area {
  let col = box.left / unit
  let row = box.top / unit
  let right = ceil_units(box.left + box.width)
  let bottom = ceil_units(box.top + box.height)
  clamp(Area(col:, row:, w: right - col, h: bottom - row))
}

fn ceil_units(px: Int) -> Int {
  { px + unit - 1 } / unit
}

/// The grid cell under a point given in design pixels.
pub fn cell_at(x: Int, y: Int) -> #(Int, Int) {
  #(
    int.clamp(x / unit, 0, layout.columns - 1),
    int.clamp(y / unit, 0, layout.rows - 1),
  )
}

/// At least one unit each way, and inside the grid: the size is cut to fit
/// first, then the area is pushed back in.
pub fn clamp(area: Area) -> Area {
  let w = int.clamp(area.w, 1, layout.columns)
  let h = int.clamp(area.h, 1, layout.rows)
  Area(
    col: int.clamp(area.col, 0, layout.columns - w),
    row: int.clamp(area.row, 0, layout.rows - h),
    w:,
    h:,
  )
}

/// A move: the area follows the pointer from the grabbed grid cell.
pub fn moved(start: Area, grab: #(Int, Int), at: #(Int, Int)) -> Area {
  clamp(
    Area(
      ..start,
      col: start.col + at.0 - grab.0,
      row: start.row + at.1 - grab.1,
    ),
  )
}

/// A resize: the hovered grid cell becomes the bottom-right corner.
pub fn resized(start: Area, at: #(Int, Int)) -> Area {
  Area(
    ..start,
    w: int.clamp(at.0 - start.col + 1, 1, layout.columns - start.col),
    h: int.clamp(at.1 - start.row + 1, 1, layout.rows - start.row),
  )
}

pub fn nudge(area: Area, dx: Int, dy: Int) -> Area {
  clamp(Area(..area, col: area.col + dx, row: area.row + dy))
}

/// Grows or shrinks from the bottom-right corner, never past the grid.
pub fn grow(area: Area, dw: Int, dh: Int) -> Area {
  resized(area, #(area.col + area.w - 1 + dw, area.row + area.h - 1 + dh))
}

/// None, then each variant in the theme's order, then none again. A variant
/// the theme no longer lists goes back to none.
pub fn next_variant(
  variants: List(String),
  current: Option(String),
) -> Option(String) {
  case current {
    None -> list.first(variants) |> option.from_result
    Some(name) ->
      case list.drop_while(variants, fn(v) { v != name }) {
        [_, next, ..] -> Some(next)
        _ -> None
      }
  }
}

/// None, start, center, end, then none again.
pub fn next_align(current: Option(Align)) -> Option(Align) {
  case current {
    None -> Some(layout.Start)
    Some(layout.Start) -> Some(layout.Center)
    Some(layout.Center) -> Some(layout.End)
    Some(layout.End) -> None
  }
}

// Drawn cells ------------------------------------------------------------------

/// The cells drawn on the slide of the selection: its content cells, in
/// source order. Notes cells are never drawn.
pub fn drawn(deck: Deck, selection: Selection) -> List(Id(CellTag)) {
  case nav.slide_of(deck, selection) {
    Ok(slide) ->
      case deck.find_slide(deck, slide) {
        Ok(slide) ->
          list.filter_map(slide.cells, fn(cell) {
            case cell.kind {
              deck.Content -> Ok(cell.id)
              deck.Notes -> Error(Nil)
            }
          })
        Error(Nil) -> []
      }
    Error(Nil) -> []
  }
}

pub fn is_drawn(deck: Deck, selection: Selection) -> Bool {
  case selection {
    OnCell(cell) -> list.contains(drawn(deck, selection), cell)
    nav.OnSlide(_) -> False
  }
}

/// The next drawn cell on the slide; from a cell that is not drawn, the
/// first one. Stays at the last.
pub fn next_drawn(deck: Deck, selection: Selection) -> Selection {
  step(drawn(deck, selection), selection)
}

pub fn previous_drawn(deck: Deck, selection: Selection) -> Selection {
  step(list.reverse(drawn(deck, selection)), selection)
}

fn step(cells: List(Id(CellTag)), selection: Selection) -> Selection {
  let after = case selection {
    OnCell(cell) ->
      case list.drop_while(cells, fn(c) { c != cell }) {
        [_, next, ..] -> Ok(next)
        [_] -> Ok(cell)
        [] -> list.first(cells)
      }
    nav.OnSlide(_) -> list.first(cells)
  }
  case after {
    Ok(cell) -> OnCell(cell)
    Error(Nil) -> selection
  }
}

/// The placed area of a cell, if it has one.
pub fn placed(layout: Layout, cell: Id(CellTag)) -> Option(Area) {
  layout.record(layout, cell).place
}
