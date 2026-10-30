//// The owner of a deck's canonical state (06-runtime.md, Ownership): one
//// actor per served folder. It applies client messages, polls the files for
//// outside edits, rebases unsaved ops onto them, and writes the files after
//// a quiet period.

import filepath
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import gleam/time/timestamp.{type Timestamp}
import zeno/deck.{type Deck}
import zeno/file
import zeno/history.{type History}
import zeno/id.{type IdSupply}
import zeno/layout.{type Layout}
import zeno/op.{type Op}
import zeno/protocol.{type ClientMsg, type Highlight, type ServerMsg, type View}
import zeno_server/highlighter
import zeno_server/store
import zeno_server/theme
import zeno_server/view

pub type Config {
  Config(
    /// The deck folder, as an absolute path.
    folder: String,
    view_file: String,
    /// Polling interval in ms (250, P18).
    poll: Int,
    /// Quiet period before writing, in ms (300).
    debounce: Int,
    /// The tree-sitter command that highlights code blocks.
    tree_sitter: String,
  )
}

pub fn config(folder: String, view_file: String) -> Config {
  Config(
    folder:,
    view_file:,
    poll: 250,
    debounce: 300,
    tree_sitter: "tree-sitter",
  )
}

pub type Message {
  /// A client connected; it receives the state and the open problems.
  Join(client: Subject(ServerMsg))
  Leave(client: Subject(ServerMsg))
  FromClient(client: Subject(ServerMsg), msg: ClientMsg)
  Poll
  Flush(generation: Int)
  /// The highlighter's answer for the deck's code blocks.
  Highlighted(blocks: List(Highlight))
}

/// Ops applied since deck.md was last read or written, kept to rebase them
/// onto an outside edit. Each group is one `Apply`, with the supply it used,
/// so a replayed `Insert` or `Duplicate` gets the same ID again. An undo or
/// redo cannot be replayed as ops.
type Pending {
  Groups(List(Group))
  Replaced
}

type Group {
  Group(ops: List(Op), supply: IdSupply)
}

/// What the server knows of a file on disk: the hash of its bytes as last
/// read or written, and why it may not be written now.
type Disk {
  Disk(seen: String, problem: Option(String))
}

type State {
  State(
    config: Config,
    self: Subject(Message),
    clients: List(Subject(ServerMsg)),
    deck: Deck,
    layout: Layout,
    history: History,
    version: Int,
    variants: List(String),
    view: View,
    /// The deck as last read from or written to deck.md.
    base: Deck,
    pending: Pending,
    deck_file: Disk,
    layout_file: Disk,
    theme_seen: String,
    /// Only the flush with the latest generation writes.
    generation: Int,
    /// Absent if it could not be started; code blocks then stay plain.
    highlighter: Option(Subject(highlighter.Message)),
    highlights: List(Highlight),
  )
}

// Start ---------------------------------------------------------------------

/// Loads the folder and starts the owner. Fails when deck.md is missing or
/// does not parse, since there is no valid state to serve.
pub fn start(config: Config) -> Result(Subject(Message), String) {
  let deck_path = path(config, "deck.md")
  use #(bytes, deck_hash) <- result.try(
    store.read(deck_path)
    |> result.replace_error(
      "No deck.md in "
      <> config.folder
      <> ". Run `zeno init "
      <> config.folder
      <> "` first.",
    ),
  )
  use deck <- result.try(case parse_deck(bytes) {
    Ok(deck) -> Ok(deck)
    Error(problem) -> Error(problem)
  })
  let now = timestamp.system_time()
  let #(layout, layout_file) = case store.read(path(config, "layout.json")) {
    Error(Nil) -> #(layout.empty(), Disk(store.missing, None))
    Ok(#(bytes, hash)) ->
      case parse_layout(bytes) {
        Ok(layout) -> #(layout, Disk(hash, None))
        Error(problem) -> #(layout.empty(), Disk(hash, Some(problem)))
      }
  }
  let layout = layout.consistency(layout, deck, now)
  let #(variants, theme_seen) = read_theme(config)
  let initialise = fn(self) {
    process.send(self, Flush(0))
    process.send_after(self, config.poll, Poll)
    let state =
      State(
        config:,
        self:,
        clients: [],
        deck:,
        layout:,
        history: history.new(deck, layout),
        version: 1,
        variants:,
        view: view.load(config.view_file, config.folder),
        base: deck,
        pending: Groups([]),
        deck_file: Disk(deck_hash, None),
        layout_file:,
        theme_seen:,
        generation: 0,
        highlighter: highlighter.start(config.tree_sitter)
          |> option.from_result,
        highlights: [],
      )
    request_highlights(state)
    actor.initialised(state) |> actor.returning(self) |> Ok
  }
  actor.new_with_initialiser(1000, initialise)
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.replace_error("The deck owner did not start.")
}

fn path(config: Config, name: String) -> String {
  filepath.join(config.folder, name)
}

fn parse_deck(bytes: BitArray) -> Result(Deck, String) {
  use text <- result.try(
    bit_array.to_string(bytes)
    |> result.replace_error("deck.md is not valid UTF-8."),
  )
  case file.parse(text, new_supply()) {
    Ok(#(deck, _)) -> Ok(deck)
    Error(file.ParseError(line:, problem:)) ->
      Error(
        "deck.md line "
        <> int.to_string(line)
        <> ": "
        <> describe_problem(problem)
        <> ".",
      )
  }
}

fn describe_problem(problem: file.Problem) -> String {
  case problem {
    file.UnknownVersion(version) ->
      "unknown format version " <> int.to_string(version)
    file.MisplacedHeader -> "the header must be the first line"
    file.SlideMarkerWithoutBreak -> "a slide marker must follow a break"
  }
}

fn parse_layout(bytes: BitArray) -> Result(Layout, String) {
  bit_array.to_string(bytes)
  |> result.replace_error(Nil)
  |> result.try(fn(text) {
    file.parse_layout(text) |> result.replace_error(Nil)
  })
  |> result.replace_error(
    "layout.json is not valid. Zeno keeps its layout and does not write"
    <> " layout.json until the file is valid again.",
  )
}

fn read_theme(config: Config) -> #(List(String), String) {
  case store.read(path(config, "theme.css")) {
    Error(Nil) -> #([], store.missing)
    Ok(#(bytes, hash)) -> #(
      theme.variants(bit_array.to_string(bytes) |> result.unwrap("")),
      hash,
    )
  }
}

/// IDs come from the clock and fresh random bits per change; the supply
/// skips live IDs either way.
pub fn new_supply() -> IdSupply {
  let #(seconds, nanoseconds) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  id.supply(
    seconds * 1000 + nanoseconds / 1_000_000,
    crypto.strong_random_bytes(8),
  )
}

// Messages ------------------------------------------------------------------

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Join(client) -> {
      greet(state, client)
      actor.continue(State(..state, clients: [client, ..state.clients]))
    }
    Leave(client) ->
      actor.continue(
        State(
          ..state,
          clients: list.filter(state.clients, fn(c) { c != client }),
        ),
      )
    FromClient(client, msg) -> actor.continue(from_client(state, client, msg))
    Poll -> {
      process.send_after(state.self, state.config.poll, Poll)
      actor.continue(state |> poll_files |> poll_theme)
    }
    Flush(generation) if generation == state.generation ->
      actor.continue(state |> poll_files |> write_files)
    Flush(_) -> actor.continue(state)
    Highlighted(blocks) -> {
      broadcast(state, protocol.Highlights(blocks))
      actor.continue(State(..state, highlights: blocks))
    }
  }
}

fn from_client(
  state: State,
  client: Subject(ServerMsg),
  msg: ClientMsg,
) -> State {
  case msg {
    protocol.Hello -> {
      greet(state, client)
      state
    }
    protocol.Apply(seq:, ops:) -> {
      let supply = new_supply()
      case op.apply_all(state.deck, ops, supply) {
        Error(error) ->
          reject(state, client, seq, protocol.describe_error(error))
        Ok(#(deck, effects, _)) -> {
          let now = timestamp.system_time()
          let layout = layout.fold_effects(state.layout, effects, now)
          let history = case ops {
            [op.EditText(cell:, ..)] ->
              history.record_edit(state.history, deck, layout, cell, now)
            _ -> history.record(state.history, deck, layout)
          }
          let pending = case state.pending {
            Groups(groups) -> Groups(list.append(groups, [Group(ops, supply)]))
            Replaced -> Replaced
          }
          State(..state, deck:, layout:, history:, pending:) |> changed
        }
      }
    }
    protocol.ApplyLayout(seq:, op:) ->
      case layout.apply(state.layout, state.deck, op) {
        Error(error) ->
          reject(state, client, seq, protocol.describe_error(error))
        Ok(layout) ->
          State(
            ..state,
            layout:,
            history: history.record(state.history, state.deck, layout),
          )
          |> changed
      }
    protocol.Undo -> step(state, client, history.undo(state.history))
    protocol.Redo -> step(state, client, history.redo(state.history))
    protocol.SaveView(view:) -> {
      case view.save(state.config.view_file, state.config.folder, view) {
        Ok(Nil) -> Nil
        Error(reason) ->
          send(client, protocol.Notice("Could not store the view: " <> reason))
      }
      State(..state, view:)
    }
  }
}

fn reject(
  state: State,
  client: Subject(ServerMsg),
  seq: Int,
  reason: String,
) -> State {
  send(client, protocol.Rejected(seq, reason))
  state
}

fn step(
  state: State,
  client: Subject(ServerMsg),
  stepped: Option(#(Deck, Layout, History)),
) -> State {
  case stepped {
    None -> {
      send(client, state_msg(state))
      state
    }
    Some(#(deck, layout, history)) -> {
      let pending = case deck == state.deck {
        True -> state.pending
        False -> Replaced
      }
      State(..state, deck:, layout:, history:, pending:) |> changed
    }
  }
}

/// After a change: a new version for every client, and a write after the
/// quiet period.
fn changed(state: State) -> State {
  let state = State(..state, version: state.version + 1)
  broadcast(state, state_msg(state))
  request_highlights(state)
  schedule_flush(state)
}

/// Asks for the tokens of the deck's code blocks; the answer comes back as
/// `Highlighted`, so a slow command never holds up the owner.
fn request_highlights(state: State) -> Nil {
  case state.highlighter {
    Some(subject) ->
      process.send(
        subject,
        highlighter.Request(protocol.code_blocks(state.deck), fn(blocks) {
          process.send(state.self, Highlighted(blocks))
        }),
      )
    None -> Nil
  }
}

fn schedule_flush(state: State) -> State {
  let generation = state.generation + 1
  process.send_after(state.self, state.config.debounce, Flush(generation))
  State(..state, generation:)
}

// Outside edits -------------------------------------------------------------

fn poll_files(state: State) -> State {
  state |> poll_deck |> poll_layout
}

fn poll_deck(state: State) -> State {
  let deck_file = state.deck_file
  case store.read(path(state.config, "deck.md")) {
    Ok(#(_, hash)) if hash == deck_file.seen -> state
    Error(Nil) if deck_file.seen == store.missing -> state
    Error(Nil) -> {
      let problem =
        "deck.md is missing. Zeno keeps the deck and does not write deck.md"
        <> " until the file is back."
      broadcast(state, protocol.Notice(problem))
      State(..state, deck_file: Disk(store.missing, Some(problem)))
    }
    Ok(#(bytes, hash)) ->
      case parse_deck(bytes) {
        Error(problem) -> {
          let problem =
            problem
            <> " Zeno keeps the last good state and does not write deck.md"
            <> " until the file parses again."
          broadcast(state, protocol.Notice(problem))
          State(..state, deck_file: Disk(hash, Some(problem)))
        }
        Ok(outside) -> {
          case deck_file.problem {
            Some(_) -> broadcast(state, protocol.Notice("deck.md reads again."))
            None -> Nil
          }
          outside_deck(State(..state, deck_file: Disk(hash, None)), outside)
        }
      }
  }
}

/// An outside edit of deck.md (06-runtime.md, Watching files): fold its
/// effects into the layout, replay the unsaved ops on top, and record the
/// result as one step.
fn outside_deck(state: State, outside: Deck) -> State {
  let now = timestamp.system_time()
  let #(layout, _) =
    layout.apply_external(state.layout, state.base, outside, now)
  let #(deck, layout, pending, dropped) =
    rebase(outside, layout, state.pending, now)
  // Records of cells that only the replayed ops bring back were orphaned by
  // the step above; the consistency step revives them.
  let layout = layout.consistency(layout, deck, now)
  case dropped {
    [] -> Nil
    _ -> broadcast(state, protocol.Notice(dropped_notice(dropped)))
  }
  let state = State(..state, base: outside, pending:)
  case deck == state.deck && layout == state.layout {
    // Only formatting changed: no step, but the canonical form is written.
    True -> schedule_flush(state)
    False ->
      State(
        ..state,
        deck:,
        layout:,
        history: history.record(state.history, deck, layout),
      )
      |> changed
  }
}

fn rebase(
  outside: Deck,
  layout: Layout,
  pending: Pending,
  now: Timestamp,
) -> #(Deck, Layout, Pending, List(String)) {
  case pending {
    Replaced -> #(outside, layout, Groups([]), [
      "an undo or redo that was not saved yet, with the changes after it",
    ])
    Groups(groups) -> {
      let #(deck, layout, kept, dropped) =
        list.fold(groups, #(outside, layout, [], []), fn(acc, group) {
          let #(deck, layout, kept, dropped) = acc
          case op.apply_all(deck, group.ops, group.supply) {
            Ok(#(deck, effects, _)) -> #(
              deck,
              layout.fold_effects(layout, effects, now),
              [group, ..kept],
              dropped,
            )
            Error(error) -> #(deck, layout, kept, [
              describe_group(group, error),
              ..dropped
            ])
          }
        })
      #(deck, layout, Groups(list.reverse(kept)), list.reverse(dropped))
    }
  }
}

fn describe_group(group: Group, error: op.OpError) -> String {
  let name = case group.ops {
    [op.EditText(..)] -> "a text edit"
    [_] -> "an edit"
    _ -> "an edit of " <> int.to_string(list.length(group.ops)) <> " steps"
  }
  name <> " (" <> protocol.describe_error(error) <> ")"
}

fn dropped_notice(dropped: List(String)) -> String {
  "deck.md was edited outside Zeno while changes were not saved yet. Dropped "
  <> string.join(dropped, ", ")
  <> ", since the edit removed what they changed."
}

fn poll_layout(state: State) -> State {
  let layout_file = state.layout_file
  case store.read(path(state.config, "layout.json")) {
    Ok(#(_, hash)) if hash == layout_file.seen -> state
    Error(Nil) if layout_file.seen == store.missing -> state
    // Zeno owns layout.json: a deleted file is written again from the
    // layout in memory.
    Error(Nil) ->
      State(..state, layout_file: Disk(store.missing, None)) |> schedule_flush
    Ok(#(bytes, hash)) ->
      case parse_layout(bytes) {
        Error(problem) -> {
          broadcast(state, protocol.Notice(problem))
          State(..state, layout_file: Disk(hash, Some(problem)))
        }
        Ok(outside) -> {
          case layout_file.problem {
            Some(_) ->
              broadcast(state, protocol.Notice("layout.json reads again."))
            None -> Nil
          }
          let now = timestamp.system_time()
          let layout = layout.consistency(outside, state.deck, now)
          let state = State(..state, layout_file: Disk(hash, None))
          case layout == state.layout {
            True -> schedule_flush(state)
            False ->
              State(
                ..state,
                layout:,
                history: history.record(state.history, state.deck, layout),
              )
              |> changed
          }
        }
      }
  }
}

fn poll_theme(state: State) -> State {
  let #(variants, seen) = read_theme(state.config)
  case seen == state.theme_seen {
    True -> state
    False -> {
      broadcast(state, protocol.ReloadTheme)
      let same = variants == state.variants
      let state = State(..state, variants:, theme_seen: seen)
      case same {
        True -> state
        False -> {
          let state = State(..state, version: state.version + 1)
          broadcast(state, state_msg(state))
          state
        }
      }
    }
  }
}

// Writing -------------------------------------------------------------------

/// deck.md first, then layout.json (06-runtime.md, Writing files). A file
/// whose printed bytes hash to what is on disk is not written.
fn write_files(state: State) -> State {
  state |> write_deck |> write_layout
}

fn write_deck(state: State) -> State {
  case state.deck_file.problem {
    Some(_) -> state
    None -> {
      let bytes = bit_array.from_string(file.print(state.deck))
      let saved = State(..state, base: state.deck, pending: Groups([]))
      case store.hash(bytes) == state.deck_file.seen {
        True -> saved
        False ->
          case store.write_atomic(path(state.config, "deck.md"), bytes) {
            Ok(hash) -> State(..saved, deck_file: Disk(hash, None))
            Error(reason) -> {
              broadcast(
                state,
                protocol.Notice("Could not write deck.md: " <> reason),
              )
              state
            }
          }
      }
    }
  }
}

fn write_layout(state: State) -> State {
  case state.layout_file.problem {
    Some(_) -> state
    None -> {
      let bytes = bit_array.from_string(file.print_layout(state.layout))
      case store.hash(bytes) == state.layout_file.seen {
        True -> state
        False ->
          case store.write_atomic(path(state.config, "layout.json"), bytes) {
            Ok(hash) -> State(..state, layout_file: Disk(hash, None))
            Error(reason) -> {
              broadcast(
                state,
                protocol.Notice("Could not write layout.json: " <> reason),
              )
              state
            }
          }
      }
    }
  }
}

// Sending -------------------------------------------------------------------

fn state_msg(state: State) -> ServerMsg {
  protocol.State(
    version: state.version,
    deck: state.deck,
    layout: state.layout,
    diagnostics: protocol.diagnostics(state.deck),
    variants: state.variants,
    view: state.view,
  )
}

/// The state, then the problems still open, so a new client sees them too.
fn greet(state: State, client: Subject(ServerMsg)) -> Nil {
  send(client, state_msg(state))
  case state.highlights {
    [] -> Nil
    blocks -> send(client, protocol.Highlights(blocks))
  }
  [state.deck_file.problem, state.layout_file.problem]
  |> option.values
  |> list.each(fn(problem) { send(client, protocol.Notice(problem)) })
}

fn broadcast(state: State, msg: ServerMsg) -> Nil {
  list.each(state.clients, send(_, msg))
}

fn send(client: Subject(ServerMsg), msg: ServerMsg) -> Nil {
  process.send(client, msg)
}
