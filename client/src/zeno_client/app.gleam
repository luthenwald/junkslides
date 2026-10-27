//// The editor's state and how it changes (05-editor.md). The server owns
//// the deck; the client keeps the last `State` it was sent, the selection,
//// the mode and the clipboard, and sends ops.

import gleam/bool
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import lustre/effect.{type Effect}
import lustre_websocket as ws
import zeno/deck.{type Cell, type Deck}
import zeno/id.{type CellTag, type Id}
import zeno/layout.{type Layout}
import zeno/op.{type EditProblem, type Op}
import zeno/protocol.{type Diagnostic, type View, View}
import zeno_client/edit
import zeno_client/keymap.{type Command, type EditCommand}
import zeno_client/nav.{type Selection, OnCell, OnSlide}

pub type Model {
  Model(
    connection: Connection,
    /// The last state from the server; `None` until the first one.
    deck: Option(Shared),
    view: View,
    selection: Selection,
    mode: Mode,
    clipboard: Option(Cell),
    /// The `seq` of the next `Apply`.
    seq: Int,
    follow: Follow,
    notice: Option(String),
    /// Changed to move keyboard focus to the selection again; see `ui`.
    focus: Int,
    /// Counts typing, so that only the last pause sends.
    typing: Int,
    dragging_divider: Bool,
  )
}

pub type Connection {
  Connecting
  Open(socket: ws.WebSocket)
  Closed
}

/// What the server sent last, apart from the view.
pub type Shared {
  Shared(
    deck: Deck,
    layout: Layout,
    diagnostics: List(Diagnostic),
    variants: List(String),
  )
}

pub type Mode {
  Command
  /// Editing one cell. `text` is the draft as typed; `drop` is set after an
  /// Esc that could not commit, so that a second Esc drops the draft.
  Editing(
    cell: Id(CellTag),
    text: String,
    problem: Option(EditProblem),
    drop: Bool,
  )
}

/// Selecting a cell the server is about to create, which only the next
/// state can name.
pub type Follow {
  Stay
  NewCell(seq: Int, edit: Bool)
}

pub type Msg {
  Socket(ws.WebSocketEvent)
  Reconnect
  CommandKey(Command)
  EditKey(EditCommand, cursor: Int)
  Select(Selection)
  StartEdit(Id(CellTag))
  Typed(Id(CellTag), String)
  TypingPaused(Int)
  Blurred(Id(CellTag))
  DividerGrab
  DividerAt(Int)
  DividerRelease
}

const typing_pause = 200

const reconnect_after = 1000

pub fn init(_flags: Nil) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      connection: Connecting,
      deck: None,
      view: protocol.default_view,
      selection: OnCell(placeholder_id()),
      mode: Command,
      clipboard: None,
      seq: 1,
      follow: Stay,
      notice: None,
      focus: 0,
      typing: 0,
      dragging_divider: False,
    )
  #(model, ws.init("/ws", Socket))
}

/// Stands in for the selection until the first state arrives.
fn placeholder_id() -> Id(CellTag) {
  let assert Ok(id) = id.parse("00000000-0000-7000-8000-000000000000")
  id
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    Socket(event) -> socket(model, event)
    Reconnect -> #(
      Model(..model, connection: Connecting),
      ws.init("/ws", Socket),
    )
    CommandKey(command) ->
      case model.deck, model.mode {
        Some(shared), Command ->
          command_key(Model(..model, notice: None), shared.deck, command)
        _, _ -> #(model, effect.none())
      }
    EditKey(command, cursor) -> edit_key(model, command, cursor)
    Select(selection) ->
      case model.mode {
        Command -> #(Model(..model, selection:), effect.none())
        Editing(..) -> #(model, effect.none())
      }
    StartEdit(cell) -> start_edit(model, cell)
    Typed(cell, text) -> typed(model, cell, text)
    TypingPaused(count) -> typing_paused(model, count)
    Blurred(cell) ->
      case model.mode {
        Editing(cell: editing, ..) if editing == cell -> commit(model, False)
        _ -> #(model, effect.none())
      }
    DividerGrab -> #(Model(..model, dragging_divider: True), effect.none())
    DividerAt(percent) ->
      case model.dragging_divider {
        True -> #(
          Model(
            ..model,
            view: View(..model.view, cells_width: int.clamp(percent, 15, 85)),
          ),
          effect.none(),
        )
        False -> #(model, effect.none())
      }
    DividerRelease ->
      case model.dragging_divider {
        True ->
          send(
            Model(..model, dragging_divider: False),
            protocol.SaveView(model.view),
          )
        False -> #(model, effect.none())
      }
  }
}

// The socket ------------------------------------------------------------------

fn socket(model: Model, event: ws.WebSocketEvent) -> #(Model, Effect(Msg)) {
  case event {
    // The server greets every new client with its state.
    ws.OnOpen(socket) -> #(
      Model(..model, connection: Open(socket)),
      effect.none(),
    )
    ws.OnTextMessage(text) ->
      case protocol.decode_server(text) {
        Ok(message) -> server(model, message)
        Error(_) -> #(
          Model(
            ..model,
            notice: Some("The server sent a message Zeno could not read."),
          ),
          effect.none(),
        )
      }
    ws.OnClose(_) | ws.InvalidUrl -> #(
      Model(..model, connection: Closed),
      after(reconnect_after, Reconnect),
    )
    ws.OnBinaryMessage(_) -> #(model, effect.none())
  }
}

fn server(model: Model, message: protocol.ServerMsg) -> #(Model, Effect(Msg)) {
  case message {
    protocol.State(deck: new, layout:, diagnostics:, variants:, view:, ..) -> {
      let old = option.map(model.deck, fn(shared) { shared.deck })
      // A divider being dragged keeps its own width until it is let go.
      // Both panes are never hidden, whatever view.json says.
      let view = case model.dragging_divider, view {
        True, _ -> model.view
        False, View(cells_hidden: True, slide_hidden: True, ..) ->
          View(..view, cells_hidden: False)
        False, view -> view
      }
      let shared = Shared(deck: new, layout:, diagnostics:, variants:)
      #(
        arrive(Model(..model, deck: Some(shared), view:), old, new),
        effect.none(),
      )
    }
    protocol.Rejected(seq:, reason:) -> {
      let follow = case model.follow {
        NewCell(seq: waiting, ..) if waiting == seq -> Stay
        follow -> follow
      }
      #(
        Model(..model, follow:, notice: Some("Not applied: " <> reason <> ".")),
        effect.none(),
      )
    }
    protocol.Notice(text) -> #(
      Model(..model, notice: Some(text)),
      effect.none(),
    )
    // Theme reloading comes with the slide pane (M4).
    protocol.ReloadTheme -> #(model, effect.none())
  }
}

/// Brings the selection, the follow and the edit mode in line with a new
/// deck.
fn arrive(model: Model, old: Option(Deck), new: Deck) -> Model {
  case old {
    None -> Model(..model, selection: nav.first(new), focus: model.focus + 1)
    Some(old) -> {
      let before = set.from_list(deck.cell_ids(old))
      let fresh =
        list.filter(deck.cell_ids(new), fn(cell) { !set.contains(before, cell) })
      case model.follow, fresh {
        // Other states may arrive first, so the follow waits for one that
        // has a new cell.
        NewCell(edit:, ..), [cell, ..] -> {
          let model = Model(..model, follow: Stay, selection: OnCell(cell))
          case edit {
            True -> enter_edit(model, new, cell)
            False -> Model(..model, focus: model.focus + 1)
          }
        }
        _, _ -> {
          let model =
            Model(..model, selection: nav.reselect(old, new, model.selection))
          case model.mode {
            Editing(cell:, text:, ..) ->
              case deck.find_cell(new, cell) {
                Ok(_) -> model
                Error(Nil) -> lost_edit(model, old, cell, text)
              }
            Command -> model
          }
        }
      }
    }
  }
}

/// The cell being edited was removed outside Zeno. Its draft goes to the
/// clipboard with its ID, so that `p` brings it back with its layout.
fn lost_edit(
  model: Model,
  old: Deck,
  cell: Id(CellTag),
  text: String,
) -> Model {
  let kind =
    deck.find_cell(old, cell)
    |> result.map(fn(at) { at.cell.kind })
    |> result.unwrap(deck.Content)
  Model(
    ..model,
    mode: Command,
    focus: model.focus + 1,
    clipboard: Some(deck.Cell(cell, kind, text)),
    notice: Some(
      "The cell being edited was removed outside Zeno. Its text is on the clipboard; p pastes it back.",
    ),
  )
}

// Command mode ------------------------------------------------------------------

fn command_key(
  model: Model,
  deck: Deck,
  command: Command,
) -> #(Model, Effect(Msg)) {
  // Every key moves focus back to the selection, which also scrolls it into
  // view.
  let model = Model(..model, follow: Stay, focus: model.focus + 1)
  let selection = model.selection
  let select = fn(selection) { #(Model(..model, selection:), effect.none()) }
  let on_cell = fn(next: fn(Id(CellTag)) -> #(Model, Effect(Msg))) {
    case selection {
      OnCell(cell) -> next(cell)
      OnSlide(_) -> #(model, effect.none())
    }
  }
  case command {
    keymap.Next -> select(nav.next(deck, selection))
    keymap.Previous -> select(nav.previous(deck, selection))
    keymap.NextSlide -> select(nav.next_slide(deck, selection))
    keymap.PreviousSlide -> select(nav.previous_slide(deck, selection))
    keymap.MoveDown ->
      on_cell(fn(cell) { move(model, nav.move_down(deck, cell), cell) })
    keymap.MoveUp ->
      on_cell(fn(cell) { move(model, nav.move_up(deck, cell), cell) })
    keymap.NewBelow -> insert(model, nav.below(deck, selection))
    keymap.NewAbove -> insert(model, nav.above(deck, selection))
    keymap.Edit ->
      case selection {
        OnCell(cell) -> #(enter_edit(model, deck, cell), effect.none())
        OnSlide(_) -> insert(model, nav.below(deck, selection))
      }
    keymap.CycleKind -> on_cell(fn(cell) { apply(model, [op.CycleKind(cell)]) })
    keymap.Cut ->
      on_cell(fn(cell) {
        let clipboard = find(deck, cell)
        let model =
          Model(
            ..model,
            clipboard: option.or(clipboard, model.clipboard),
            selection: nav.after_removal(deck, cell),
          )
        apply(model, [op.Delete(cell)])
      })
    keymap.Copy ->
      on_cell(fn(cell) {
        #(
          Model(..model, clipboard: find(deck, cell), notice: Some("Copied.")),
          effect.none(),
        )
      })
    keymap.PasteBelow -> paste(model, nav.below(deck, selection))
    keymap.PasteAbove -> paste(model, nav.above(deck, selection))
    keymap.Duplicate ->
      on_cell(fn(cell) { follow(model, [op.Duplicate(cell)], False) })
    keymap.Merge -> on_cell(fn(cell) { apply(model, [op.MergeWithNext(cell)]) })
    keymap.BreakHere ->
      on_cell(fn(cell) {
        case nav.above(deck, OnCell(cell)) {
          Ok(deck.Position(index: 0, ..)) -> #(
            Model(..model, notice: Some("This cell already starts a slide.")),
            effect.none(),
          )
          Ok(at) -> apply(model, [op.InsertBreak(at)])
          Error(Nil) -> #(model, effect.none())
        }
      })
    keymap.RemoveBreak ->
      case nav.slide_of(deck, selection) {
        Ok(slide) -> apply(model, [op.RemoveBreak(slide)])
        Error(Nil) -> #(model, effect.none())
      }
    keymap.Undo -> send(model, protocol.Undo)
    keymap.Redo -> send(model, protocol.Redo)
    keymap.ToggleCells -> {
      let view = model.view
      let cells_hidden = !view.cells_hidden
      let slide_hidden = view.slide_hidden && !cells_hidden
      save_view(model, View(..view, cells_hidden:, slide_hidden:))
    }
    keymap.ToggleSlide -> {
      let view = model.view
      let slide_hidden = !view.slide_hidden
      let cells_hidden = view.cells_hidden && !slide_hidden
      save_view(model, View(..view, cells_hidden:, slide_hidden:))
    }
  }
}

fn move(
  model: Model,
  to: Result(deck.Position, Nil),
  cell: Id(CellTag),
) -> #(Model, Effect(Msg)) {
  case to {
    Ok(to) -> apply(model, [op.Move(cell, to)])
    Error(Nil) -> #(model, effect.none())
  }
}

fn insert(
  model: Model,
  at: Result(deck.Position, Nil),
) -> #(Model, Effect(Msg)) {
  case at {
    Ok(at) -> follow(model, [op.Insert(at, deck.Content)], True)
    Error(Nil) -> #(model, effect.none())
  }
}

fn paste(
  model: Model,
  at: Result(deck.Position, Nil),
) -> #(Model, Effect(Msg)) {
  case model.clipboard, at {
    Some(cell), Ok(at) -> follow(model, [op.Paste(cell, at)], False)
    None, _ -> #(
      Model(..model, notice: Some("The clipboard is empty.")),
      effect.none(),
    )
    _, Error(Nil) -> #(model, effect.none())
  }
}

fn find(deck: Deck, cell: Id(CellTag)) -> Option(Cell) {
  deck.find_cell(deck, cell)
  |> result.map(fn(at) { at.cell })
  |> option.from_result
}

fn save_view(model: Model, view: View) -> #(Model, Effect(Msg)) {
  send(Model(..model, view:), protocol.SaveView(view))
}

// Edit mode ------------------------------------------------------------------

fn enter_edit(model: Model, deck: Deck, cell: Id(CellTag)) -> Model {
  case find(deck, cell) {
    Some(found) ->
      Model(
        ..model,
        selection: OnCell(cell),
        mode: Editing(cell:, text: found.source, problem: None, drop: False),
        focus: model.focus + 1,
      )
    None -> model
  }
}

/// A text area got focus, by a click or by entering edit mode.
fn start_edit(model: Model, cell: Id(CellTag)) -> #(Model, Effect(Msg)) {
  case model.mode, model.deck {
    Editing(cell: editing, ..), _ if editing == cell -> #(model, effect.none())
    // Leaving another cell commits it first; if that fails, focus goes back.
    Editing(..), Some(shared) -> {
      let #(committed, effects) = commit(model, False)
      case committed.mode {
        Command -> #(enter_edit(committed, shared.deck, cell), effects)
        Editing(..) -> #(committed, effects)
      }
    }
    Command, Some(shared) -> #(
      enter_edit(Model(..model, notice: None), shared.deck, cell),
      effect.none(),
    )
    _, None -> #(model, effect.none())
  }
}

fn typed(
  model: Model,
  cell: Id(CellTag),
  text: String,
) -> #(Model, Effect(Msg)) {
  case model.mode, model.deck {
    Editing(cell: editing, ..), Some(shared) if editing == cell -> {
      let problem = case edit.while_typing(shared.deck, cell, text) {
        Ok(_) -> None
        Error(problem) -> Some(problem)
      }
      let typing = model.typing + 1
      #(
        Model(
          ..model,
          typing:,
          mode: Editing(cell:, text:, problem:, drop: False),
        ),
        after(typing_pause, TypingPaused(typing)),
      )
    }
    _, _ -> #(model, effect.none())
  }
}

fn typing_paused(model: Model, count: Int) -> #(Model, Effect(Msg)) {
  use <- bool.guard(count != model.typing, #(model, effect.none()))
  case model.mode, model.deck {
    Editing(cell:, text:, ..), Some(shared) ->
      case edit.while_typing(shared.deck, cell, text) {
        Ok([]) | Error(_) -> #(model, effect.none())
        Ok(ops) -> apply(model, ops)
      }
    _, _ -> #(model, effect.none())
  }
}

fn edit_key(
  model: Model,
  command: EditCommand,
  cursor: Int,
) -> #(Model, Effect(Msg)) {
  case command, model.mode, model.deck {
    keymap.Commit, Editing(..), _ -> commit(model, True)
    keymap.SplitHere, Editing(cell:, text:, ..), Some(shared) ->
      case edit.split(shared.deck, cell, text, cursor) {
        Ok(ops) -> {
          let model = Model(..model, typing: model.typing + 1, mode: Command)
          follow(model, ops, True)
        }
        Error(edit.HasBreak) -> #(
          Model(
            ..model,
            notice: Some(
              "This cell has a --- line. Press Esc to commit it first.",
            ),
          ),
          effect.none(),
        )
        Error(edit.Problem(problem)) -> #(
          Model(..model, notice: Some(edit.describe(problem))),
          effect.none(),
        )
      }
    _, _, _ -> #(model, effect.none())
  }
}

/// Commits the draft and returns to command mode. A draft with a marker
/// line cannot be committed: edit mode stays, and focus returns to it. With
/// `by_escape`, a second Esc drops the draft.
fn commit(model: Model, by_escape: Bool) -> #(Model, Effect(Msg)) {
  case model.mode, model.deck, model.connection {
    // Offline, the draft stays in its cell rather than being lost.
    Editing(..), _, Connecting | Editing(..), _, Closed -> #(
      Model(
        ..model,
        focus: model.focus + 1,
        notice: Some(
          "Not connected to the server. The text stays here; press Esc again once the connection is back.",
        ),
      ),
      effect.none(),
    )
    Editing(cell:, text:, drop:, ..), Some(shared), Open(_) -> {
      let leave =
        Model(
          ..model,
          mode: Command,
          typing: model.typing + 1,
          focus: model.focus + 1,
        )
      case edit.commit(shared.deck, cell, text) {
        Ok([]) -> #(leave, effect.none())
        Ok(ops) -> apply(leave, ops)
        Error(_) if drop && by_escape -> #(
          Model(..leave, notice: Some("The change to this cell was dropped.")),
          effect.none(),
        )
        Error(op.EditUnknownCell) -> #(leave, effect.none())
        Error(problem) -> #(
          Model(
            ..model,
            mode: Editing(cell:, text:, problem: Some(problem), drop: by_escape),
            focus: model.focus + 1,
            notice: Some(
              edit.describe(problem)
              <> " Fix it, or press Esc twice to drop the change.",
            ),
          ),
          effect.none(),
        )
      }
    }
    _, _, _ -> #(Model(..model, mode: Command), effect.none())
  }
}

// Sending ------------------------------------------------------------------

fn apply(model: Model, ops: List(Op)) -> #(Model, Effect(Msg)) {
  send(Model(..model, seq: model.seq + 1), protocol.Apply(model.seq, ops))
}

/// Applies ops that create a cell, and selects that cell once the server
/// has made it.
fn follow(model: Model, ops: List(Op), edit: Bool) -> #(Model, Effect(Msg)) {
  apply(Model(..model, follow: NewCell(model.seq, edit)), ops)
}

fn send(model: Model, message: protocol.ClientMsg) -> #(Model, Effect(Msg)) {
  case model.connection {
    Open(socket) -> #(model, ws.send(socket, protocol.encode_client(message)))
    Connecting | Closed -> #(
      Model(
        ..model,
        notice: Some("Not connected to the server; the change was not sent."),
      ),
      effect.none(),
    )
  }
}

fn after(ms: Int, msg: Msg) -> Effect(Msg) {
  use dispatch <- effect.from
  promise.wait(ms)
  |> promise.map(fn(_) { dispatch(msg) })
  Nil
}
