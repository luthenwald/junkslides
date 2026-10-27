import gleam/dict
import gleam/option.{None, Some}
import gleam/time/timestamp
import support/fixture.{cell, slide}
import zeno/deck.{Position}
import zeno/layout.{
  Area, CellOrphan, CellRecord, Center, Place, PurgeOrphans, SetAlign,
  SetVariant, Unplace,
}
import zeno/op.{AreaOutsideGrid, Fresh, Retired, Revived, UnknownCell}

const now = timestamp.unix_epoch

fn styled() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  let assert Ok(layout) =
    layout.apply(layout.empty(), deck, Place(a.id, Area(1, 1, 4, 2)))
  let assert Ok(layout) =
    layout.apply(layout, deck, SetVariant(a.id, Some("large")))
  let assert Ok(layout) =
    layout.apply(layout, deck, SetAlign(a.id, Some(Center)))
  #(deck, supply, layout, a)
}

pub fn layout_ops_test() {
  let #(deck, _, layout, a) = styled()
  assert layout.record(layout, a.id)
    == CellRecord(Some(Area(1, 1, 4, 2)), Some("large"), Some(Center))
  assert layout.apply(layout, deck, Place(a.id, Area(30, 0, 3, 1)))
    == Error(AreaOutsideGrid)
  assert layout.apply(layout, deck, Place(a.id, Area(0, 0, 0, 1)))
    == Error(AreaOutsideGrid)
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
