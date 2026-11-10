import gleam/option.{None, Some}
import gleam/time/timestamp
import junkslides/layout.{Area, Place}
import junkslides/op
import junkslides/session
import support/fixture.{cell}

const now = timestamp.unix_epoch

/// A session applies ops and layout ops, one undo step each, and steps back
/// and forward through them; a refused op leaves it as it was.
pub fn a_session_applies_and_steps_test() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  let start = session.new(deck, layout.empty())
  assert session.undo(start) == None
  let assert Ok(placed) =
    session.apply_layout(start, Place(a.id, Area(60, 60, 240, 120)))
  assert layout.record(placed.layout, a.id).place
    == Some(Area(60, 60, 240, 120))
  let assert Ok(cut) = session.apply(placed, [op.Delete(a.id)], supply, now)
  // The effect reached the layout: the record waits among the orphans.
  let assert [layout.CellOrphan(..)] = cut.layout.orphans
  let assert Some(back) = session.undo(cut)
  assert back.deck == deck
  assert back.layout == placed.layout
  let assert Some(forward) = session.redo(back)
  assert forward.deck == cut.deck
  let assert Some(first) = session.undo(back)
  assert first.layout == layout.empty()
  assert session.undo(first) == None
  // Refused, and nothing recorded.
  let assert Error(op.UnknownCell(_)) =
    session.apply(cut, [op.Delete(a.id)], supply, now)
  let assert Error(op.AreaOffSlide) =
    session.apply_layout(start, Place(a.id, Area(0, 0, 0, 0)))
}
