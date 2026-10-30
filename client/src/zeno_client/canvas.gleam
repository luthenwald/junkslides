//// Canvas arithmetic (04-layout.md, Placing and moving): areas from drawn
//// boxes, and moves, resizes and nudges in design pixels that snap to a
//// step and stay on the slide, and the cycles of variant and alignment.
//// Pure, so it is unit tested.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import zeno/deck.{type Deck}
import zeno/id.{type CellTag, type Id}
import zeno/layout.{type Align, type Area, type Layout, Area}
import zeno_client/nav.{type Selection, OnCell}

/// The snap step in design pixels.
pub const snap_step = 60

/// A drawn cell's box in design pixels, relative to the slide.
pub type Box {
  Box(left: Int, top: Int, width: Int, height: Int)
}

/// The area a drawn box covers, exactly as drawn.
pub fn area_of_box(box: Box) -> Area {
  clamp(Area(x: box.left, y: box.top, w: box.width, h: box.height))
}

/// The nearest multiple of the step; a step of one or less is no snapping.
pub fn snap(px: Int, step: Int) -> Int {
  case step > 1 {
    True -> floor(px + step / 2, step)
    False -> px
  }
}

/// The multiple of the step `by` steps from `px`, counting the first line
/// in that direction as one: from 125 with a step of 30, one step on is 150
/// and one step back is 120.
fn step_from(px: Int, by: Int, step: Int) -> Int {
  let step = int.max(step, 1)
  case int.compare(by, 0) {
    order.Eq -> px
    order.Gt -> floor(px, step) + by * step
    order.Lt -> ceil(px, step) + by * step
  }
}

fn floor(px: Int, step: Int) -> Int {
  case int.floor_divide(px, step) {
    Ok(n) -> n * step
    Error(Nil) -> px
  }
}

fn ceil(px: Int, step: Int) -> Int {
  0 - floor(0 - px, step)
}

/// At least one pixel each way, at most the slide, and on the slide: the
/// size is cut to fit first, then the area is pushed back in.
pub fn clamp(area: Area) -> Area {
  let w = int.clamp(area.w, 1, layout.width)
  let h = int.clamp(area.h, 1, layout.height)
  Area(
    x: int.clamp(area.x, 0, layout.width - w),
    y: int.clamp(area.y, 0, layout.height - h),
    w:,
    h:,
  )
}

/// A move: the area follows the pointer from the grabbed point, and its
/// top left corner snaps.
pub fn moved(
  start: Area,
  grab: #(Int, Int),
  at: #(Int, Int),
  step: Int,
) -> Area {
  clamp(
    Area(
      ..start,
      x: snap(start.x + at.0 - grab.0, step),
      y: snap(start.y + at.1 - grab.1, step),
    ),
  )
}

/// A resize: the snapped point becomes the bottom-right corner, at least
/// one step from the top left one.
pub fn resized(start: Area, at: #(Int, Int), step: Int) -> Area {
  let least = int.max(step, 1)
  Area(
    ..start,
    w: int.clamp(snap(at.0, step) - start.x, least, layout.width - start.x),
    h: int.clamp(snap(at.1, step) - start.y, least, layout.height - start.y),
  )
}

/// A move by whole steps, onto the step's lines.
pub fn nudge(area: Area, dx: Int, dy: Int, step: Int) -> Area {
  clamp(
    Area(..area, x: step_from(area.x, dx, step), y: step_from(area.y, dy, step)),
  )
}

/// Grows or shrinks from the bottom-right corner by whole steps, onto the
/// step's lines, never past the slide. A shrink stops one step from the top
/// left corner.
pub fn grow(area: Area, dw: Int, dh: Int, step: Int) -> Area {
  let least = int.max(step, 1)
  let right = step_from(area.x + area.w, dw, step)
  let bottom = step_from(area.y + area.h, dh, step)
  Area(
    ..area,
    w: int.clamp(right - area.x, int.min(least, area.w), layout.width - area.x),
    h: int.clamp(
      bottom - area.y,
      int.min(least, area.h),
      layout.height - area.y,
    ),
  )
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
