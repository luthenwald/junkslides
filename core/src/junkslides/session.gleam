//// One editing session over a deck and its layout: what a client's edits,
//// layout changes, undo and redo do to them (06-runtime.md). The server's
//// owner and the editor that runs without a server both go through here,
//// so the two cannot drift apart. Pure: IDs and time come as arguments.

import gleam/option.{type Option, None, Some}
import gleam/time/timestamp.{type Timestamp}
import junkslides/deck.{type Deck}
import junkslides/history.{type History}
import junkslides/id.{type IdSupply}
import junkslides/layout.{type Layout, type LayoutOp}
import junkslides/op.{type Op, type OpError}

pub type Session {
  Session(deck: Deck, layout: Layout, history: History)
}

/// A session that starts from these files, with nothing to undo.
pub fn new(deck: Deck, layout: Layout) -> Session {
  Session(deck, layout, history.new(deck, layout))
}

/// Applies a group of ops, all or none, folds their effects into the
/// layout, and records one undo step. Typing in one cell joins the step
/// before it (`history.record_edit`).
pub fn apply(
  session: Session,
  ops: List(Op),
  supply: IdSupply,
  now: Timestamp,
) -> Result(Session, OpError) {
  case op.apply_all(session.deck, ops, supply) {
    Error(error) -> Error(error)
    Ok(#(deck, effects, _)) -> {
      let layout = layout.fold_effects(session.layout, effects, now)
      let history = case ops {
        [op.EditText(cell:, ..)] ->
          history.record_edit(session.history, deck, layout, cell, now)
        _ -> history.record(session.history, deck, layout)
      }
      Ok(Session(deck:, layout:, history:))
    }
  }
}

/// Applies a layout op and records one undo step.
pub fn apply_layout(
  session: Session,
  op: LayoutOp,
) -> Result(Session, OpError) {
  case layout.apply(session.layout, session.deck, op) {
    Error(error) -> Error(error)
    Ok(layout) ->
      Ok(
        Session(
          ..session,
          layout:,
          history: history.record(session.history, session.deck, layout),
        ),
      )
  }
}

/// One step back, or `None` when there is none.
pub fn undo(session: Session) -> Option(Session) {
  stepped(history.undo(session.history))
}

/// One step forward again, or `None` when there is none.
pub fn redo(session: Session) -> Option(Session) {
  stepped(history.redo(session.history))
}

fn stepped(step: Option(#(Deck, Layout, History))) -> Option(Session) {
  case step {
    None -> None
    Some(#(deck, layout, history)) -> Some(Session(deck:, layout:, history:))
  }
}
