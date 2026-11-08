//// Undo and redo by bounded snapshots (03-data-model.md, History; P14).

import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import junkslides/deck.{type Deck}
import junkslides/id.{type CellTag, type Id}
import junkslides/layout.{type Layout}

pub const limit = 500

type Snapshot {
  Snapshot(deck: Deck, layout: Layout)
}

/// The present state, the states before it (newest first, at most `limit`)
/// and the states undone (newest first). `typing` is set while the present
/// step is a run of text edits on one cell that later edits may join.
pub opaque type History {
  History(
    past: List(Snapshot),
    present: Snapshot,
    future: List(Snapshot),
    typing: Option(#(Id(CellTag), Timestamp)),
  )
}

pub fn new(deck: Deck, layout: Layout) -> History {
  History([], Snapshot(deck, layout), [], None)
}

pub fn present(history: History) -> #(Deck, Layout) {
  #(history.present.deck, history.present.layout)
}

/// Records a new state as one step. The redo stack is cleared.
pub fn record(history: History, deck: Deck, layout: Layout) -> History {
  History(
    past: [history.present, ..history.past] |> list.take(limit),
    present: Snapshot(deck, layout),
    future: [],
    typing: None,
  )
}

/// Records the state after a text edit of `cell`. Edits of the same cell
/// coalesce into the present step while they fall within one second of the
/// first edit of that step.
pub fn record_edit(
  history: History,
  deck: Deck,
  layout: Layout,
  cell: Id(CellTag),
  now: Timestamp,
) -> History {
  case history.typing {
    Some(#(typing, started)) if typing == cell && history.future == [] ->
      case
        duration.compare(
          timestamp.difference(started, now),
          duration.seconds(1),
        )
      {
        order.Lt | order.Eq ->
          History(..history, present: Snapshot(deck, layout))
        _ -> start_typing(history, deck, layout, cell, now)
      }
    _ -> start_typing(history, deck, layout, cell, now)
  }
}

fn start_typing(
  history: History,
  deck: Deck,
  layout: Layout,
  cell: Id(CellTag),
  now: Timestamp,
) -> History {
  History(..record(history, deck, layout), typing: Some(#(cell, now)))
}

pub fn undo(history: History) -> Option(#(Deck, Layout, History)) {
  case history.past {
    [] -> None
    [previous, ..past] ->
      Some(#(
        previous.deck,
        previous.layout,
        History(
          past:,
          present: previous,
          future: [history.present, ..history.future],
          typing: None,
        ),
      ))
  }
}

pub fn redo(history: History) -> Option(#(Deck, Layout, History)) {
  case history.future {
    [] -> None
    [next, ..future] ->
      Some(#(
        next.deck,
        next.layout,
        History(
          past: [history.present, ..history.past] |> list.take(limit),
          present: next,
          future:,
          typing: None,
        ),
      ))
  }
}

pub fn can_undo(history: History) -> Bool {
  history.past != []
}

pub fn can_redo(history: History) -> Bool {
  history.future != []
}
