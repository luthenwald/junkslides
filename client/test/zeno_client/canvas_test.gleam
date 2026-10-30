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

pub fn a_box_is_placed_as_drawn_test() {
  assert canvas.area_of_box(Box(left: 130, top: 120, width: 600, height: 61))
    == Area(x: 130, y: 120, w: 600, h: 61)
  // At least a pixel, and ten pixels from the slide's far edges.
  assert canvas.area_of_box(Box(left: 0, top: 0, width: 0, height: 0))
    == Area(x: 9, y: 9, w: 1, h: 1)
  // A box may hang off the slide; one too far off is pushed back until ten
  // pixels show, and one larger than the slide is cut to its size.
  assert canvas.area_of_box(Box(left: 1800, top: 1000, width: 400, height: 400))
    == Area(x: 1800, y: 1000, w: 400, h: 400)
  assert canvas.area_of_box(Box(left: -900, top: 1075, width: 400, height: 2000))
    == Area(x: -390, y: 1070, w: 400, h: 1080)
}

pub fn snapping_rounds_to_the_nearest_step_test() {
  assert canvas.snap(44, 30) == 30
  assert canvas.snap(45, 30) == 60
  assert canvas.snap(-44, 30) == -30
  assert canvas.snap(127, 10) == 130
  // Off: every pixel.
  assert canvas.snap(127, 1) == 127
}

pub fn moves_follow_the_grab_and_snap_test() {
  let start = Area(x: 240, y: 180, w: 360, h: 120)
  // The pointer moves by (190, 175): the corner lands at (430, 355), which
  // snaps to (420, 360) with a step of 60 and (430, 360) with 10.
  assert canvas.moved(start, #(300, 200), #(490, 375), 60)
    == Area(x: 420, y: 360, w: 360, h: 120)
  assert canvas.moved(start, #(300, 200), #(490, 375), 10)
    == Area(x: 430, y: 360, w: 360, h: 120)
  // Past the edges, as far as ten pixels left on the slide.
  assert canvas.moved(start, #(300, 200), #(560, 260), 60)
    == Area(x: 480, y: 240, w: 360, h: 120)
  assert canvas.moved(start, #(560, 260), #(0, 0), 60)
    == Area(x: -300, y: -60, w: 360, h: 120)
  assert canvas.moved(start, #(300, 200), #(5000, 5000), 60)
    == Area(x: 1910, y: 1070, w: 360, h: 120)
  assert canvas.moved(start, #(300, 200), #(-5000, -5000), 60)
    == Area(x: -350, y: -110, w: 360, h: 120)
}

pub fn resizes_keep_one_step_and_the_slide_test() {
  let start = Area(x: 240, y: 180, w: 360, h: 120)
  assert canvas.resized(start, #(770, 590), 60)
    == Area(x: 240, y: 180, w: 540, h: 420)
  assert canvas.resized(start, #(0, 0), 30)
    == Area(x: 240, y: 180, w: 30, h: 30)
  // Past the right edge, up to the slide's size.
  assert canvas.resized(start, #(2500, 300), 60)
    == Area(x: 240, y: 180, w: 1920, h: 120)
  // A box hanging off the left keeps ten pixels on the slide.
  assert canvas.resized(Area(x: -300, y: 0, w: 360, h: 60), #(0, 0), 60)
    == Area(x: -300, y: 0, w: 310, h: 60)
  assert canvas.grow(start, 1, -1, 60) == Area(x: 240, y: 180, w: 420, h: 60)
  assert canvas.grow(start, 0, -1, 60) |> canvas.grow(0, -1, 60)
    == Area(x: 240, y: 180, w: 360, h: 60)
  assert canvas.grow(Area(x: 1800, y: 0, w: 120, h: 60), 1, 0, 60)
    == Area(x: 1800, y: 0, w: 180, h: 60)
  assert canvas.grow(Area(x: 0, y: 0, w: 1920, h: 60), 1, 0, 60)
    == Area(x: 0, y: 0, w: 1920, h: 60)
  // An edge off the step's lines moves onto the next one.
  assert canvas.grow(Area(x: 125, y: 0, w: 100, h: 60), 1, 0, 30)
    == Area(x: 125, y: 0, w: 115, h: 60)
}

pub fn nudges_move_onto_the_lines_and_stop_off_the_edge_test() {
  assert canvas.nudge(Area(x: 0, y: 1020, w: 180, h: 60), -1, 1, 60)
    == Area(x: -60, y: 1070, w: 180, h: 60)
  assert canvas.nudge(Area(x: 1910, y: 0, w: 180, h: 60), 1, 0, 60)
    == Area(x: 1910, y: 0, w: 180, h: 60)
  assert canvas.nudge(Area(x: 300, y: 300, w: 180, h: 60), 1, -1, 60)
    == Area(x: 360, y: 240, w: 180, h: 60)
  assert canvas.nudge(Area(x: 125, y: 125, w: 180, h: 60), 1, -1, 30)
    == Area(x: 150, y: 120, w: 180, h: 60)
  assert canvas.nudge(Area(x: 125, y: 125, w: 180, h: 60), 1, 0, 1)
    == Area(x: 126, y: 125, w: 180, h: 60)
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
