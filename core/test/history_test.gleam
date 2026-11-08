import gleam/option.{None, Some}
import gleam/time/duration
import gleam/time/timestamp
import junkslides/deck
import junkslides/history
import junkslides/layout
import junkslides/op
import support/fixture.{cell}

fn edit(d: deck.Deck, text: String) -> deck.Deck {
  let #(_, supply) = fixture.deck()
  let assert Ok(#(after, _, _)) =
    op.apply(d, op.EditText(cell(d, 0, 0).id, text), supply)
  after
}

pub fn undo_redo_test() {
  let #(d0, _) = fixture.deck()
  let l = layout.empty()
  let d1 = edit(d0, "one")
  let d2 = edit(d1, "two")
  let h = history.new(d0, l) |> history.record(d1, l) |> history.record(d2, l)
  let assert Some(#(back, _, h)) = history.undo(h)
  assert back == d1
  let assert Some(#(back, _, h)) = history.undo(h)
  assert back == d0
  assert history.undo(h) == None
  let assert Some(#(forward, _, h)) = history.redo(h)
  assert forward == d1
  // A new step clears the redo stack.
  let h = history.record(h, d0, l)
  assert history.redo(h) == None
}

pub fn bounded_test() {
  let #(d0, _) = fixture.deck()
  let l = layout.empty()
  let h = repeat(history.new(d0, l), 600, fn(h) { history.record(h, d0, l) })
  assert count_undos(h, 0) == history.limit
}

fn repeat(h, n, f) {
  case n {
    0 -> h
    _ -> repeat(f(h), n - 1, f)
  }
}

fn count_undos(h, n) {
  case history.undo(h) {
    Some(#(_, _, h)) -> count_undos(h, n + 1)
    None -> n
  }
}

pub fn coalescing_test() {
  let #(d0, _) = fixture.deck()
  let a = cell(d0, 0, 0).id
  let b = cell(d0, 0, 1).id
  let l = layout.empty()
  let at = fn(ms) {
    timestamp.add(timestamp.unix_epoch, duration.milliseconds(ms))
  }
  let d1 = edit(d0, "o")
  let d2 = edit(d1, "on")
  let d3 = edit(d2, "one")
  let d4 = edit(d3, "one!")
  let h =
    history.new(d0, l)
    |> history.record_edit(d1, l, a, at(0))
    |> history.record_edit(d2, l, a, at(400))
    |> history.record_edit(d3, l, a, at(1000))
    // More than a second after the step began: a new step.
    |> history.record_edit(d4, l, a, at(1200))
  let assert Some(#(back, _, h)) = history.undo(h)
  assert back == d3
  let assert Some(#(back, _, _)) = history.undo(h)
  assert back == d0
  // Another cell starts a new step.
  let h =
    history.new(d0, l)
    |> history.record_edit(d1, l, a, at(0))
    |> history.record_edit(d2, l, b, at(100))
  let assert Some(#(back, _, _)) = history.undo(h)
  assert back == d1
}
