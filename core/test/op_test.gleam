import gleam/option.{None, Some}
import junkslides/deck.{Cell, Content, Notes, Position}
import junkslides/op.{
  CycleKind, Delete, DeleteOnlySlide, DeleteSlide, Duplicate, EditText, Fresh,
  Insert, InsertBreak, MarkerLine, MergeWithNext, Move, MoveSlide, NoNextCell,
  Paste, PositionOutOfRange, RemoveBreak, RemoveFirstBreak, Retired, Revived,
  SlideFresh, SlideRetired, Split, Unnormalised,
}
import support/fixture.{cell, slide, sources}

pub fn edit_text_test() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  let assert Ok(#(after, [], _)) = op.apply(deck, EditText(a.id, "A"), supply)
  assert sources(after) == [["A", "b", "c"], ["d"], []]
  assert op.apply(deck, EditText(a.id, "x\n---\ny"), supply)
    == Error(Unnormalised)
  assert op.apply(deck, EditText(a.id, "x\n"), supply) == Error(Unnormalised)
}

pub fn insert_and_delete_test() {
  let #(deck, supply) = fixture.deck()
  let s1 = slide(deck, 1)
  let assert Ok(#(after, [Fresh(new, None)], _)) =
    op.apply(deck, Insert(Position(s1.id, 0), Notes), supply)
  assert cell(after, 1, 0) == Cell(new, Notes, "")
  assert op.apply(deck, Insert(Position(s1.id, 2), Notes), supply)
    == Error(PositionOutOfRange)
  let d = cell(deck, 1, 0)
  let assert Ok(#(after, [Retired(gone)], _)) =
    op.apply(deck, Delete(d.id), supply)
  assert gone == d.id
  assert sources(after) == [["a", "b", "c"], [], []]
}

pub fn split_test() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  let assert Ok(#(deck, _, supply)) =
    op.apply(deck, EditText(a.id, "one\n\n\ntwo"), supply)
  let assert Ok(#(after, [Fresh(new, Some(from))], _)) =
    op.apply(deck, Split(a.id, 4), supply)
  assert from == a.id
  assert sources(after) == [["one", "two", "b", "c"], ["d"], []]
  assert cell(after, 0, 1).id == new
  assert cell(after, 0, 0).id == a.id
  assert op.apply(deck, Split(a.id, 99), supply) == Error(PositionOutOfRange)
  // Notes split into notes.
  let c = cell(deck, 0, 2)
  let assert Ok(#(after, _, _)) = op.apply(deck, Split(c.id, 0), supply)
  assert cell(after, 0, 3) == Cell(cell(after, 0, 3).id, Notes, "c")
}

pub fn merge_test() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  let b = cell(deck, 0, 1)
  let assert Ok(#(after, [Retired(gone)], _)) =
    op.apply(deck, MergeWithNext(a.id), supply)
  assert gone == b.id
  assert sources(after) == [["a\n\nb", "c"], ["d"], []]
  let c = cell(deck, 0, 2)
  assert op.apply(deck, MergeWithNext(c.id), supply) == Error(NoNextCell)
}

pub fn move_test() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  // The index is read after removal.
  let assert Ok(#(after, [], _)) =
    op.apply(deck, Move(a.id, Position(slide(deck, 0).id, 2)), supply)
  assert sources(after) == [["b", "c", "a"], ["d"], []]
  let assert Ok(#(after, [], _)) =
    op.apply(deck, Move(a.id, Position(slide(deck, 2).id, 0)), supply)
  assert sources(after) == [["b", "c"], ["d"], ["a"]]
  assert op.apply(deck, Move(a.id, Position(slide(deck, 0).id, 3)), supply)
    == Error(PositionOutOfRange)
}

pub fn duplicate_and_cycle_test() {
  let #(deck, supply) = fixture.deck()
  let c = cell(deck, 0, 2)
  let assert Ok(#(after, [Fresh(copy, Some(from))], _)) =
    op.apply(deck, Duplicate(c.id), supply)
  assert from == c.id
  assert cell(after, 0, 3) == Cell(copy, Notes, "c")
  let assert Ok(#(after, [], _)) = op.apply(deck, CycleKind(c.id), supply)
  assert cell(after, 0, 2).kind == Content
}

pub fn paste_rule_test() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  let at = Position(slide(deck, 2).id, 0)
  // Copy then paste: the ID is live, so the paste gets a fresh one.
  let assert Ok(#(copied, [Fresh(new, Some(from))], supply)) =
    op.apply(deck, Paste(a, at), supply)
  assert from == a.id && new != a.id
  assert sources(copied) == [["a", "b", "c"], ["d"], ["a"]]
  // Cut then paste: the ID was retired, so it is reused.
  let assert Ok(#(cut, _, supply)) = op.apply(deck, Delete(a.id), supply)
  let assert Ok(#(pasted, [Revived(back)], supply)) =
    op.apply(cut, Paste(a, at), supply)
  assert back == a.id
  // Pasting the same cut again gives a fresh ID.
  let assert Ok(#(_, [Fresh(_, Some(_))], _)) =
    op.apply(pasted, Paste(a, at), supply)
  assert op.apply(deck, Paste(Cell(..a, source: "\nx"), at), supply)
    == Error(Unnormalised)
}

pub fn breaks_test() {
  let #(deck, supply) = fixture.deck()
  let s0 = slide(deck, 0)
  let assert Ok(#(after, [SlideFresh(new)], _)) =
    op.apply(deck, InsertBreak(Position(s0.id, 1)), supply)
  assert sources(after) == [["a"], ["b", "c"], ["d"], []]
  assert slide(after, 1).id == new
  let s1 = slide(deck, 1)
  let assert Ok(#(after, [SlideRetired(gone)], _)) =
    op.apply(deck, RemoveBreak(s1.id), supply)
  assert gone == s1.id
  assert sources(after) == [["a", "b", "c", "d"], []]
  assert op.apply(deck, RemoveBreak(s0.id), supply) == Error(RemoveFirstBreak)
}

pub fn slides_test() {
  let #(deck, supply) = fixture.deck()
  let s0 = slide(deck, 0)
  let assert Ok(#(after, [], _)) = op.apply(deck, MoveSlide(s0.id, 2), supply)
  assert sources(after) == [["d"], [], ["a", "b", "c"]]
  assert op.apply(deck, MoveSlide(s0.id, 3), supply)
    == Error(PositionOutOfRange)
  let assert Ok(#(
    after,
    [SlideRetired(_), Retired(_), Retired(_), Retired(_)],
    _,
  )) = op.apply(deck, DeleteSlide(s0.id), supply)
  assert sources(after) == [["d"], []]
  let assert Ok(#(after, _, supply)) =
    op.apply_all(after, [DeleteSlide(slide(after, 1).id)], supply)
  assert op.apply(after, DeleteSlide(slide(after, 0).id), supply)
    == Error(DeleteOnlySlide)
}

pub fn apply_all_is_all_or_nothing_test() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  assert op.apply_all(
      deck,
      [EditText(a.id, "x"), MergeWithNext(cell(deck, 0, 2).id)],
      supply,
    )
    == Error(NoNextCell)
}

pub fn normalize_plain_edit_test() {
  let #(deck, _) = fixture.deck()
  let a = cell(deck, 0, 0)
  assert op.normalize_edit(deck, a.id, "\n\nnew text\n\n")
    == Ok([EditText(a.id, "new text")])
  assert op.normalize_edit(deck, a.id, "a") == Ok([])
  assert op.normalize_edit(deck, a.id, "x\n<!-- notes -->\ny")
    == Error(MarkerLine(2))
  assert op.normalize_edit(deck, a.id, "<!-- deck v1 -->")
    == Error(MarkerLine(1))
}

pub fn normalize_breaks_test() {
  let #(deck, supply) = fixture.deck()
  let b = cell(deck, 0, 1)
  let check = fn(typed, expected) {
    let assert Ok(ops) = op.normalize_edit(deck, b.id, typed)
    let assert Ok(#(after, _, _)) = op.apply_all(deck, ops, supply)
    assert sources(after) == expected
    assert cell(after, 0, 1).id == b.id
  }
  check("one\n---\ntwo", [["a", "one"], ["two", "c"], ["d"], []])
  check("one\n---\ntwo\n---\nthree", [
    ["a", "one"],
    ["two"],
    ["three", "c"],
    ["d"],
    [],
  ])
  check("---\ntwo", [["a", ""], ["two", "c"], ["d"], []])
  check("one\n---", [["a", "one"], ["", "c"], ["d"], []])
  check("one\n---\n---\nthree", [["a", "one"], [""], ["three", "c"], ["d"], []])
  check("```\ncode\n---\nmore\n```", [
    ["a", "```\ncode"],
    ["more\n```", "c"],
    ["d"],
    [],
  ])
}

pub fn split_never_creates_a_structural_line_test() {
  let #(deck, supply) = fixture.deck()
  let a = cell(deck, 0, 0)
  let assert Ok(#(deck, _, supply)) =
    op.apply(deck, EditText(a.id, "x\n ---\n<!-- cell -->y"), supply)
  assert op.apply(deck, Split(a.id, 3), supply) == Error(Unnormalised)
  assert op.apply(deck, Split(a.id, 20), supply) == Error(Unnormalised)
  let assert Ok(_) = op.apply(deck, Split(a.id, 2), supply)
}
