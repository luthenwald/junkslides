import zeno/deck.{Cell, Content, Deck, Position, Slide}
import zeno/id.{type Id}
import zeno/op
import zeno_client/edit

fn id(n: String) -> Id(tag) {
  let assert Ok(id) = id.parse("019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e" <> n)
  id
}

fn deck(source: String) -> deck.Deck {
  Deck([Slide(id("01"), [Cell(id("a1"), Content, source)])])
}

pub fn typing_sends_normalised_text_test() {
  let d = deck("Hello")
  assert edit.while_typing(d, id("a1"), "Hello") == Ok([])
  // A new line being started is not sent as a trailing blank line.
  assert edit.while_typing(d, id("a1"), "Hello\n\n") == Ok([])
  assert edit.while_typing(d, id("a1"), "Hello\nworld\n")
    == Ok([op.EditText(id("a1"), "Hello\nworld")])
}

pub fn a_break_waits_for_the_commit_test() {
  let d = deck("Hello")
  let text = "Hello\n---\nNext"
  assert edit.while_typing(d, id("a1"), text) == Ok([])
  assert edit.commit(d, id("a1"), text)
    == Ok([
      op.EditText(id("a1"), "Hello\n\nNext"),
      op.Split(id("a1"), 5),
      op.InsertBreak(Position(id("01"), 1)),
    ])
}

pub fn marker_lines_are_problems_test() {
  let d = deck("Hello")
  assert edit.while_typing(d, id("a1"), "Hello\n<!-- cell -->")
    == Error(op.MarkerLine(2))
}

pub fn split_at_the_cursor_test() {
  let d = deck("Hello")
  assert edit.split(d, id("a1"), "Hello", 2) == Ok([op.Split(id("a1"), 2)])
  // Leading blank lines are dropped on commit, and the cut moves with them.
  assert edit.split(d, id("a1"), "\n\nab cd", 5)
    == Ok([op.EditText(id("a1"), "ab cd"), op.Split(id("a1"), 3)])
  assert edit.split(d, id("a1"), "a\n---\nb", 1) == Error(edit.HasBreak)
}

pub fn cursor_counts_utf16_units_test() {
  // An emoji outside the basic plane is two UTF-16 units and one grapheme.
  assert edit.graphemes_before("a😀b", 3) == 2
  assert edit.graphemes_before("a😀b", 2) == 1
  assert edit.graphemes_before("abc", 9) == 3
}
