import zeno/deck.{Cell, Content, Deck, Position, Slide}
import zeno/id.{type Id}
import zeno_client/nav.{OnCell, OnSlide}

fn id(n: String) -> Id(tag) {
  let assert Ok(id) = id.parse("019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e" <> n)
  id
}

/// Slide s1 holds a and b, s2 is empty, s3 holds c.
fn deck() -> deck.Deck {
  Deck([
    Slide(id("01"), [Cell(id("a1"), Content, "A"), Cell(id("b1"), Content, "B")]),
    Slide(id("02"), []),
    Slide(id("03"), [Cell(id("c1"), Content, "C")]),
  ])
}

pub fn items_include_empty_slides_test() {
  assert nav.items(deck())
    == [OnCell(id("a1")), OnCell(id("b1")), OnSlide(id("02")), OnCell(id("c1"))]
}

pub fn next_and_previous_stop_at_the_ends_test() {
  let d = deck()
  assert nav.next(d, OnCell(id("b1"))) == OnSlide(id("02"))
  assert nav.next(d, OnCell(id("c1"))) == OnCell(id("c1"))
  assert nav.previous(d, OnSlide(id("02"))) == OnCell(id("b1"))
  assert nav.previous(d, OnCell(id("a1"))) == OnCell(id("a1"))
}

pub fn slide_jumps_test() {
  let d = deck()
  assert nav.next_slide(d, OnCell(id("b1"))) == OnSlide(id("02"))
  assert nav.next_slide(d, OnSlide(id("02"))) == OnCell(id("c1"))
  assert nav.next_slide(d, OnCell(id("c1"))) == OnCell(id("c1"))
  assert nav.previous_slide(d, OnCell(id("c1"))) == OnSlide(id("02"))
  assert nav.previous_slide(d, OnCell(id("b1"))) == OnCell(id("b1"))
}

pub fn moves_cross_slides_test() {
  let d = deck()
  assert nav.move_down(d, id("a1")) == Ok(Position(id("01"), 1))
  assert nav.move_down(d, id("b1")) == Ok(Position(id("02"), 0))
  assert nav.move_down(d, id("c1")) == Error(Nil)
  assert nav.move_up(d, id("b1")) == Ok(Position(id("01"), 0))
  assert nav.move_up(d, id("c1")) == Ok(Position(id("02"), 0))
  assert nav.move_up(d, id("a1")) == Error(Nil)
}

pub fn new_cells_go_below_or_above_test() {
  let d = deck()
  assert nav.below(d, OnCell(id("a1"))) == Ok(Position(id("01"), 1))
  assert nav.above(d, OnCell(id("a1"))) == Ok(Position(id("01"), 0))
  assert nav.below(d, OnSlide(id("02"))) == Ok(Position(id("02"), 0))
}

pub fn removal_selects_a_neighbour_on_the_slide_test() {
  let d = deck()
  assert nav.after_removal(d, id("a1")) == OnCell(id("b1"))
  assert nav.after_removal(d, id("b1")) == OnCell(id("a1"))
  assert nav.after_removal(d, id("c1")) == OnSlide(id("03"))
}

pub fn slide_removal_selects_the_next_slide_test() {
  let d = deck()
  assert nav.after_slide_removal(d, id("01")) == OnSlide(id("02"))
  assert nav.after_slide_removal(d, id("02")) == OnCell(id("c1"))
  // The last slide goes to the end of the one before it.
  assert nav.after_slide_removal(d, id("03")) == OnSlide(id("02"))
  let two =
    Deck([
      Slide(id("01"), [
        Cell(id("a1"), Content, "A"),
        Cell(id("b1"), Content, "B"),
      ]),
      Slide(id("03"), []),
    ])
  assert nav.after_slide_removal(two, id("03")) == OnCell(id("b1"))
}

pub fn reselect_keeps_the_place_test() {
  let d = deck()
  let without_b =
    Deck([
      Slide(id("01"), [Cell(id("a1"), Content, "A")]),
      Slide(id("02"), []),
      Slide(id("03"), [Cell(id("c1"), Content, "C")]),
    ])
  assert nav.reselect(d, without_b, OnCell(id("a1"))) == OnCell(id("a1"))
  // b was the second place; the second place is now the empty slide.
  assert nav.reselect(d, without_b, OnCell(id("b1"))) == OnSlide(id("02"))
  let short = Deck([Slide(id("01"), [Cell(id("a1"), Content, "A")])])
  assert nav.reselect(d, short, OnCell(id("c1"))) == OnCell(id("a1"))
}

pub fn numbers_are_padded_test() {
  assert nav.number(0, 12) == "01/12"
  assert nav.number(4, 9) == "05/09"
  assert nav.number(6, 120) == "007/120"
}
