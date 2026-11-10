import gleam/dict
import gleam/option.{None, Some}
import gleam/string
import gleam/time/timestamp
import junkslides/deck.{Position}
import junkslides/file
import junkslides/id
import junkslides/layout.{
  Area, CellOrphan, CellRecord, Center, Place, PurgeOrphans, SetAlign, SetSlide,
  SetVariant, SlideOrphan, SlideRecord, Unplace,
}
import junkslides/op.{
  AreaOffSlide, Fresh, Retired, Revived, SlideRetired, UnknownCell,
}
import support/fixture.{cell, slide}

const now = timestamp.unix_epoch

fn styled() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  let assert Ok(layout) =
    layout.apply(layout.empty(), deck, Place(a.id, Area(60, 60, 240, 120)))
  let assert Ok(layout) =
    layout.apply(layout, deck, SetVariant(a.id, Some("large")))
  let assert Ok(layout) =
    layout.apply(layout, deck, SetAlign(a.id, Some(Center)))
  #(deck, supply, layout, a)
}

pub fn layout_ops_test() {
  let #(deck, _, layout, a) = styled()
  assert layout.record(layout, a.id)
    == CellRecord(Some(Area(60, 60, 240, 120)), Some("large"), Some(Center))
  // Parts may lie off the slide, as long as ten pixels stay on it each way.
  let assert Ok(_) =
    layout.apply(layout, deck, Place(a.id, Area(-190, -50, 200, 60)))
  let assert Ok(_) =
    layout.apply(layout, deck, Place(a.id, Area(1910, 1070, 300, 300)))
  assert layout.apply(layout, deck, Place(a.id, Area(-191, 0, 200, 60)))
    == Error(AreaOffSlide)
  assert layout.apply(layout, deck, Place(a.id, Area(0, 1071, 200, 60)))
    == Error(AreaOffSlide)
  assert layout.apply(layout, deck, Place(a.id, Area(0, 0, 0, 60)))
    == Error(AreaOffSlide)
  assert layout.apply(layout, deck, Place(a.id, Area(0, 0, 1921, 60)))
    == Error(AreaOffSlide)
  // An empty record is not stored.
  let assert Ok(cleared) = layout.apply(layout, deck, Unplace(a.id))
  let assert Ok(cleared) = layout.apply(cleared, deck, SetVariant(a.id, None))
  let assert Ok(cleared) = layout.apply(cleared, deck, SetAlign(a.id, None))
  assert dict.is_empty(cleared.cells)
}

pub fn layout_op_on_unknown_cell_test() {
  let #(deck, supply, layout, a) = styled()
  let assert Ok(#(cut, _, _)) = op.apply(deck, op.Delete(a.id), supply)
  assert layout.apply(layout, cut, Unplace(a.id)) == Error(UnknownCell(a.id))
}

pub fn fold_effects_test() {
  let #(deck, supply, layout, a) = styled()
  // Split: the second part inherits variant and align, not placement.
  let assert Ok(#(_, effects, _)) = op.apply(deck, op.Split(a.id, 0), supply)
  let assert [Fresh(new, Some(_))] = effects
  let split = layout.fold_effects(layout, effects, now)
  assert layout.record(split, new)
    == CellRecord(None, Some("large"), Some(Center))
  // Retire then revive brings the record back whole.
  let retired = layout.fold_effects(layout, [Retired(a.id)], now)
  assert dict.is_empty(retired.cells)
  let assert [CellOrphan(id, _, _)] = retired.orphans
  assert id == a.id
  let revived = layout.fold_effects(retired, [Revived(a.id)], now)
  assert revived == layout
  let assert Ok(purged) = layout.apply(retired, deck, PurgeOrphans)
  assert purged.orphans == []
}

pub fn consistency_test() {
  let #(deck, supply, layout, a) = styled()
  let assert Ok(#(cut, _, _)) = op.apply(deck, op.Delete(a.id), supply)
  // A crash between the two writes leaves a record for a dead cell.
  let repaired = layout.consistency(layout, cut, now)
  assert dict.is_empty(repaired.cells)
  assert layout.consistency(repaired, deck, now) == layout
}

pub fn external_edit_test() {
  let #(deck, supply, layout, a) = styled()
  let assert Ok(#(cut, _, supply)) = op.apply(deck, op.Delete(a.id), supply)
  let #(orphaned, effects) = layout.apply_external(layout, deck, cut, now)
  assert effects == [Retired(a.id)]
  let at = Position(slide(cut, 1).id, 0)
  let assert Ok(#(back, _, _)) = op.apply(cut, op.Paste(a, at), supply)
  let #(restored, effects) = layout.apply_external(orphaned, cut, back, now)
  assert effects == [Revived(a.id)]
  assert restored == layout
  assert restored.orphans == []
}

/// A slide's switches (D33): a record with something off is kept, one with
/// everything on is not, the file names only what is off, and a slide that
/// goes and comes back keeps them.
pub fn slide_switches_test() {
  let #(deck, _) = fixture.deck()
  let s = slide(deck, 0)
  let off = SlideRecord(number: False, marks: True)
  let assert Ok(set) = layout.apply(layout.empty(), deck, SetSlide(s.id, off))
  assert layout.slide_record(set, s.id) == off
  let text = file.print_layout(set)
  assert string.contains(text, "\"number\": false")
  assert !string.contains(text, "marks")
  assert file.parse_layout(text) == Ok(set)
  let both = SlideRecord(number: False, marks: False)
  let assert Ok(none) = layout.apply(set, deck, SetSlide(s.id, both))
  assert file.parse_layout(file.print_layout(none)) == Ok(none)
  // Everything on again leaves no record.
  let assert Ok(cleared) =
    layout.apply(set, deck, SetSlide(s.id, layout.no_slide_record))
  assert cleared == layout.empty()
  assert layout.slide_record(cleared, s.id) == layout.no_slide_record
  // Gone from the deck and back: the record waits among the orphans.
  let retired = layout.fold_effects(none, [SlideRetired(s.id)], now)
  assert dict.is_empty(retired.slides)
  let assert [SlideOrphan(record:, ..)] = retired.orphans
  assert record == both
  assert file.parse_layout(file.print_layout(retired)) == Ok(retired)
  assert layout.consistency(retired, deck, now) == none
  // An older file's empty record reads as everything on.
  let assert Ok(old) =
    file.parse_layout(
      "{\"version\": 2, \"cells\": {}, \"slides\": {\""
      <> id.to_string(s.id)
      <> "\": {}}}",
    )
  assert layout.slide_record(old, s.id) == layout.no_slide_record
}
