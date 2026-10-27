import gleam/option.{None, Some}
import zeno/deck.{Cell, Content, Deck, Notes, Slide}
import zeno/id.{type Id}
import zeno/layout.{Area}
import zeno_client/canvas.{Box}
import zeno_client/nav.{OnCell, OnSlide}

fn id(n: String) -> Id(tag) {
  let assert Ok(id) = id.parse("019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e" <> n)
  id
}

pub fn a_box_covers_whole_units_test() {
  // 130 px from the left starts in column 2; its right edge at 730 px ends
  // inside column 12, so it covers columns 2 to 12.
  assert canvas.area_of_box(Box(left: 130, top: 120, width: 600, height: 61))
    == Area(col: 2, row: 2, w: 11, h: 2)
  assert canvas.area_of_box(Box(left: 0, top: 0, width: 0, height: 0))
    == Area(col: 0, row: 0, w: 1, h: 1)
  // A box hanging off the slide keeps its size and is pushed back in.
  assert canvas.area_of_box(Box(left: 1800, top: 1000, width: 400, height: 400))
    == Area(col: 25, row: 10, w: 7, h: 8)
}

pub fn moves_follow_the_grab_and_stay_in_the_grid_test() {
  let start = Area(col: 4, row: 3, w: 6, h: 2)
  assert canvas.moved(start, #(5, 3), #(8, 6))
    == Area(col: 7, row: 6, w: 6, h: 2)
  assert canvas.moved(start, #(5, 3), #(31, 17))
    == Area(col: 26, row: 16, w: 6, h: 2)
  assert canvas.moved(start, #(9, 4), #(0, 0))
    == Area(col: 0, row: 0, w: 6, h: 2)
}

pub fn resizes_keep_one_unit_and_the_grid_test() {
  let start = Area(col: 4, row: 3, w: 6, h: 2)
  assert canvas.resized(start, #(12, 9)) == Area(col: 4, row: 3, w: 9, h: 7)
  assert canvas.resized(start, #(0, 0)) == Area(col: 4, row: 3, w: 1, h: 1)
  assert canvas.grow(start, 1, -1) == Area(col: 4, row: 3, w: 7, h: 1)
  assert canvas.grow(start, 0, -1) |> canvas.grow(0, -1)
    == Area(col: 4, row: 3, w: 6, h: 1)
  assert canvas.grow(Area(col: 30, row: 0, w: 2, h: 1), 1, 0)
    == Area(col: 30, row: 0, w: 2, h: 1)
}

pub fn nudges_stop_at_the_edge_test() {
  assert canvas.nudge(Area(col: 0, row: 17, w: 3, h: 1), -1, 1)
    == Area(col: 0, row: 17, w: 3, h: 1)
  assert canvas.nudge(Area(col: 5, row: 5, w: 3, h: 1), 1, -1)
    == Area(col: 6, row: 4, w: 3, h: 1)
}

pub fn variants_cycle_through_none_test() {
  let variants = ["large", "small"]
  assert canvas.next_variant(variants, None) == Some("large")
  assert canvas.next_variant(variants, Some("large")) == Some("small")
  assert canvas.next_variant(variants, Some("small")) == None
  assert canvas.next_variant(variants, Some("gone")) == None
  assert canvas.next_variant([], None) == None
}

pub fn alignment_cycles_through_none_test() {
  assert canvas.next_align(None) == Some(layout.Start)
  assert canvas.next_align(Some(layout.End)) == None
}

pub fn drawn_cells_skip_notes_test() {
  let d =
    Deck([
      Slide(id("01"), [
        Cell(id("a1"), Content, "A"),
        Cell(id("f1"), Notes, "N"),
        Cell(id("b1"), Content, "B"),
      ]),
      Slide(id("02"), []),
    ])
  assert canvas.drawn(d, OnCell(id("f1"))) == [id("a1"), id("b1")]
  assert canvas.next_drawn(d, OnCell(id("a1"))) == OnCell(id("b1"))
  assert canvas.next_drawn(d, OnCell(id("b1"))) == OnCell(id("b1"))
  assert canvas.next_drawn(d, OnCell(id("f1"))) == OnCell(id("a1"))
  assert canvas.previous_drawn(d, OnCell(id("b1"))) == OnCell(id("a1"))
  assert canvas.next_drawn(d, OnSlide(id("02"))) == OnSlide(id("02"))
  assert !canvas.is_drawn(d, OnCell(id("f1")))
}
