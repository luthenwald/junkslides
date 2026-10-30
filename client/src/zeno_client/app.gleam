//// The editor's state and how it changes (05-editor.md). The server owns
//// the deck; the client keeps the last `State` it was sent, the selection,
//// the mode and the clipboard, and sends ops.

import gleam/bool
import gleam/dict.{type Dict}
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
import zeno/layout.{type Area, type Layout}
import zeno/op.{type EditProblem, type Op}
import zeno/protocol.{type Diagnostic, type View, View}
import zeno_client/canvas.{type Box}
import zeno_client/edit
import zeno_client/keymap.{type CanvasCommand, type Command, type EditCommand}
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
    /// A cell being moved or resized on the canvas.
    drag: Option(Drag),
    /// What each cell's overflow probe reported last; see `slide`.
    overflow: Dict(Id(CellTag), Bool),
    /// Counts theme reloads; the theme's URL carries it.
    theme: Int,
    /// The latest reload whose stylesheet has arrived. Its link stays until
    /// the newer one has loaded, so the slide is never drawn without a
    /// theme.
    theme_loaded: Int,
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
  /// The slide pane has the keys (05-editor.md, Canvas mode).
  Canvas
  /// Editing one cell. `text` is the draft as typed; `drop` is set after an
  /// Esc that could not commit, so that a second Esc drops the draft.
  Editing(
    cell: Id(CellTag),
    text: String,
    problem: Option(EditProblem),
    drop: Bool,
  )
}

/// A drag on the canvas shows `area` as a preview and sends one `Place` when
/// let go. `released` is then that op's `seq`, and the preview stays until a
/// state shows the cell at `area`, so the cell does not jump back while the
/// op travels, also when other states arrive first.
pub type Drag {
  Drag(
    cell: Id(CellTag),
    how: DragKind,
    start: Area,
    area: Area,
    released: Option(Int),
  )
}

pub type DragKind {
  /// `grab` is the point the pointer pressed, in design pixels.
  Moving(grab: #(Int, Int))
  Resizing
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
  CanvasKey(CanvasCommand, Option(Box))
  /// A press on a drawn cell at a point of the slide, in design pixels.
  Grab(cell: Id(CellTag), x: Int, y: Int, box: Box)
  GrabHandle(Id(CellTag))
  /// The pointer during a drag, at a point of the slide in design pixels.
  DragTo(x: Int, y: Int)
  DragEnd
  Probe(cell: Id(CellTag), overflows: Bool)
  ThemeLoaded(Int)
  /// The time a released drag waits for its state is up.
  DragSettled(seq: Int)
}

const typing_pause = 200

/// How long a released drag's preview waits for a state that shows it,
/// should that state never come (an outside edit placed the cell elsewhere).
const drag_settle = 1000

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
      drag: None,
      overflow: dict.new(),
      theme: 0,
      theme_loaded: 0,
    )
  #(model, ws.init("/.zeno/ws", Socket))
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
      ws.init("/.zeno/ws", Socket),
    )
    CommandKey(command) ->
      case model.deck, model.mode {
        Some(shared), Command ->
          command_key(Model(..model, notice: None), shared, command)
        _, _ -> #(model, effect.none())
      }
    EditKey(command, cursor) -> edit_key(model, command, cursor)
    Select(selection) ->
      case model.mode {
        Command | Canvas -> #(
          Model(..model, selection:, mode: Command),
          effect.none(),
        )
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
    CanvasKey(command, box) ->
      case model.deck, model.mode {
        Some(shared), Canvas ->
          canvas_key(Model(..model, notice: None), shared, command, box)
        _, _ -> #(model, effect.none())
      }
    Grab(cell:, x:, y:, box:) ->
      grab(
        model,
        cell,
        fn(start) { Drag(cell, Moving(#(x, y)), start, start, None) },
        Some(box),
      )
    GrabHandle(cell) ->
      grab(
        model,
        cell,
        fn(start) { Drag(cell, Resizing, start, start, None) },
        None,
      )
    DragTo(x:, y:) ->
      case model.drag {
        Some(Drag(released: None, how:, start:, area: before, ..) as drag) -> {
          let area = case how {
            Moving(grab) -> canvas.moved(start, grab, #(x, y), canvas.snap_step)
            Resizing -> canvas.resized(start, #(x, y), canvas.snap_step)
          }
          case area == before {
            True -> #(model, effect.none())
            False -> #(
              Model(..model, drag: Some(Drag(..drag, area:))),
              effect.none(),
            )
          }
        }
        _ -> #(model, effect.none())
      }
    DragEnd ->
      case model.drag {
        Some(Drag(released: None, cell:, start:, area:, ..) as drag)
          if area != start
        -> {
          let seq = model.seq
          let model =
            Model(..model, drag: Some(Drag(..drag, released: Some(seq))))
          let #(model, effects) = apply_layout(model, layout.Place(cell, area))
          case model.connection {
            Open(_) -> #(
              model,
              effect.batch([effects, after(drag_settle, DragSettled(seq))]),
            )
            Connecting | Closed -> #(Model(..model, drag: None), effects)
          }
        }
        Some(Drag(released: None, ..)) -> #(
          Model(..model, drag: None),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    Probe(cell:, overflows:) -> #(
      Model(..model, overflow: dict.insert(model.overflow, cell, overflows)),
      effect.none(),
    )
    DragSettled(seq:) ->
      case model.drag {
        Some(Drag(released: Some(sent), ..)) if sent == seq -> #(
          Model(..model, drag: None),
          effect.none(),
        )
        _ -> #(model, effect.none())
      }
    ThemeLoaded(n) -> #(
      Model(..model, theme_loaded: int.max(model.theme_loaded, n)),
      effect.none(),
    )
  }
}

/// The drawn cells whose probes report overflow.
pub fn overflowing(model: Model, shared: Shared) -> List(Id(CellTag)) {
  deck.cells(shared.deck)
  |> list.filter_map(fn(cell) {
    case cell.kind, dict.get(model.overflow, cell.id) {
      deck.Content, Ok(True) -> Ok(cell.id)
      _, _ -> Error(Nil)
    }
  })
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
      let drag = case model.drag {
        Some(Drag(released: Some(_), cell:, area:, ..) as drag) -> {
          let landed = layout.record(layout, cell).place == Some(area)
          let gone = result.is_error(deck.find_cell(new, cell))
          case landed || gone {
            True -> None
            False -> Some(drag)
          }
        }
        drag -> drag
      }
      let mode = case model.mode, view.slide_hidden {
        Canvas, True -> Command
        mode, _ -> mode
      }
      #(
        arrive(
          Model(..model, deck: Some(shared), view:, drag:, mode:),
          old,
          new,
        ),
        effect.none(),
      )
    }
    protocol.Rejected(seq:, reason:) -> {
      let follow = case model.follow {
        NewCell(seq: waiting, ..) if waiting == seq -> Stay
        follow -> follow
      }
      let drag = case model.drag {
        Some(Drag(released: Some(sent), ..)) if sent == seq -> None
        drag -> drag
      }
      #(
        Model(
          ..model,
          follow:,
          drag:,
          notice: Some("Not applied: " <> reason <> "."),
        ),
        effect.none(),
      )
    }
    protocol.Notice(text) -> #(
      Model(..model, notice: Some(text)),
      effect.none(),
    )
    // A new URL makes the browser fetch the theme again.
    protocol.ReloadTheme -> #(
      Model(..model, theme: model.theme + 1),
      effect.none(),
    )
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
            Command | Canvas -> model
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
  shared: Shared,
  command: Command,
) -> #(Model, Effect(Msg)) {
  let deck = shared.deck
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
    keymap.PurgeOrphans ->
      case list.length(shared.layout.orphans) {
        0 -> #(
          Model(..model, notice: Some("There are no orphans.")),
          effect.none(),
        )
        1 ->
          Model(..model, notice: Some("Removed 1 orphan; u brings it back."))
          |> apply_layout(layout.PurgeOrphans)
        n ->
          Model(
            ..model,
            notice: Some(
              "Removed " <> int.to_string(n) <> " orphans; u brings them back.",
            ),
          )
          |> apply_layout(layout.PurgeOrphans)
      }
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
    keymap.ToCanvas ->
      case model.view.slide_hidden {
        True -> #(
          Model(
            ..model,
            notice: Some("The slide pane is hidden; Ctrl-] shows it."),
          ),
          effect.none(),
        )
        False -> #(Model(..model, mode: Canvas), effect.none())
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
        Command | Canvas -> #(enter_edit(committed, shared.deck, cell), effects)
        Editing(..) -> #(committed, effects)
      }
    }
    Command, Some(shared) | Canvas, Some(shared) -> #(
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

// Canvas mode ------------------------------------------------------------------

fn canvas_key(
  model: Model,
  shared: Shared,
  command: CanvasCommand,
  box: Option(Box),
) -> #(Model, Effect(Msg)) {
  let model = Model(..model, focus: model.focus + 1)
  let deck = shared.deck
  let select = fn(selection) { #(Model(..model, selection:), effect.none()) }
  // Keys that change a drawn cell. An unplaced cell's area is where it is
  // drawn, read from the focused element when the key was pressed.
  let on_drawn = fn(
    next: fn(Id(CellTag), Option(Area)) -> #(Model, Effect(Msg)),
  ) {
    case model.selection, canvas.is_drawn(deck, model.selection) {
      OnCell(cell), True ->
        next(
          cell,
          option.or(
            canvas.placed(shared.layout, cell),
            option.map(box, canvas.area_of_box),
          ),
        )
      _, _ -> #(model, effect.none())
    }
  }
  let place = fn(cell, from: Option(Area), change: fn(Area) -> Area) {
    case from {
      Some(area) ->
        case change(area), canvas.placed(shared.layout, cell) {
          // At the edge of the grid nothing changes, and nothing is sent.
          new, Some(old) if new == old -> #(model, effect.none())
          new, _ -> apply_layout(model, layout.Place(cell, new))
        }
      None -> #(model, effect.none())
    }
  }
  case command {
    keymap.NextDrawn -> select(canvas.next_drawn(deck, model.selection))
    keymap.PreviousDrawn -> select(canvas.previous_drawn(deck, model.selection))
    keymap.PlaceHere ->
      on_drawn(fn(cell, area) {
        case canvas.placed(shared.layout, cell) {
          Some(_) -> #(
            Model(..model, notice: Some("This cell is already placed.")),
            effect.none(),
          )
          None -> place(cell, area, fn(area) { area })
        }
      })
    keymap.Nudge(dx:, dy:) ->
      on_drawn(fn(cell, area) {
        place(cell, area, canvas.nudge(_, dx, dy, canvas.snap_step))
      })
    keymap.Resize(dw:, dh:) ->
      on_drawn(fn(cell, area) {
        place(cell, area, canvas.grow(_, dw, dh, canvas.snap_step))
      })
    keymap.ReturnToFlow ->
      on_drawn(fn(cell, _) {
        case canvas.placed(shared.layout, cell) {
          Some(_) -> apply_layout(model, layout.Unplace(cell))
          None -> #(model, effect.none())
        }
      })
    keymap.CycleVariant ->
      on_drawn(fn(cell, _) {
        let current = layout.record(shared.layout, cell).variant
        let variant = canvas.next_variant(shared.variants, current)
        apply_layout(model, layout.SetVariant(cell, variant))
      })
    keymap.CycleAlign ->
      on_drawn(fn(cell, _) {
        let align = canvas.next_align(layout.record(shared.layout, cell).align)
        apply_layout(model, layout.SetAlign(cell, align))
      })
    keymap.CanvasUndo -> send(model, protocol.Undo)
    keymap.CanvasRedo -> send(model, protocol.Redo)
    keymap.ToCells -> #(Model(..model, mode: Command), effect.none())
  }
}

/// A press on a drawn cell or its handle: an edit in progress is committed
/// first, then the cell is selected in canvas mode and the drag starts.
fn grab(
  model: Model,
  cell: Id(CellTag),
  drag: fn(Area) -> Drag,
  box: Option(Box),
) -> #(Model, Effect(Msg)) {
  let #(model, effects) = case model.mode {
    Editing(..) -> commit(model, False)
    Command | Canvas -> #(model, effect.none())
  }
  case model.mode, model.deck {
    Editing(..), _ | _, None -> #(model, effects)
    _, Some(shared) -> {
      let start =
        option.or(
          canvas.placed(shared.layout, cell),
          option.map(box, canvas.area_of_box),
        )
      let model =
        Model(
          ..model,
          mode: Canvas,
          selection: OnCell(cell),
          focus: model.focus + 1,
          notice: None,
          drag: option.map(start, drag),
        )
      #(model, effects)
    }
  }
}

// Sending ------------------------------------------------------------------

fn apply_layout(model: Model, op: layout.LayoutOp) -> #(Model, Effect(Msg)) {
  send(Model(..model, seq: model.seq + 1), protocol.ApplyLayout(model.seq, op))
}

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
