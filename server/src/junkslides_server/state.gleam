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
import junkslides/contract
import junkslides/deck.{type Deck}
import junkslides/file
import junkslides/history.{type History}
import junkslides/id.{type IdSupply}
import junkslides/layout.{type Layout}
import junkslides/op.{type Op}
import junkslides/protocol.{
  type ClientMsg, type Highlight, type ServerMsg, type View,
}
import junkslides/session.{type Session, Session}
import junkslides/settings
import junkslides/shade
import junkslides_server/export
import junkslides_server/figures
import junkslides_server/highlighter
import junkslides_server/pdf
import junkslides_server/store
import junkslides_server/view
import simplifile

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
  /// An export's outcome, for the client that asked for it.
  Exported(client: Subject(ServerMsg), outcome: Result(export.Report, String))
  /// The stylesheet from junkslides.toml as last read well, for `/.js/settings.css`.
  SettingsCss(reply: Subject(String))
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

/// junkslides.toml as far as the editor needs it: the hash last read, the stylesheet
/// from the last version that read well (empty without the file), why the
/// file on disk does not read, and the font files it names that are missing.
/// junkslides never writes it.
type SettingsFile {
  SettingsFile(
    seen: String,
    css: String,
    problem: Option(String),
    missing: List(String),
    /// The simple shading's rules (D30), from the last settings that read.
    shading: shade.Rules,
  )
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
    /// The theme's mark classes (D28), for the diagnostics.
    marks: List(String),
    view: View,
    /// The deck as last read from or written to deck.md.
    base: Deck,
    pending: Pending,
    deck_file: Disk,
    layout_file: Disk,
    /// Why the last write of deck.md or layout.json failed, until one works.
    deck_write: Option(String),
    layout_write: Option(String),
    theme_seen: String,
    settings_file: SettingsFile,
    /// Only the flush with the latest generation writes.
    generation: Int,
    /// Absent if it could not be started; code blocks then stay plain.
    highlighter: Option(Subject(highlighter.Message)),
    highlights: List(Highlight),
    /// The deck's drawings and charts as last read (D29).
    figures: List(#(String, figures.File)),
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
      <> ". Run `junkslides init "
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
  let #(variants, marks, theme_seen) = read_theme(config)
  let settings_file =
    read_settings(
      config,
      SettingsFile(store.missing, "", None, [], shade.default_rules),
    )
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
        marks:,
        view: view.load(config.view_file, config.folder),
        base: deck,
        pending: Groups([]),
        deck_file: Disk(deck_hash, None),
        layout_file:,
        deck_write: None,
        layout_write: None,
        theme_seen:,
        settings_file:,
        generation: 0,
        highlighter: highlighter.start(config.tree_sitter)
          |> option.from_result,
        highlights: [],
        figures: [],
      )
    request_highlights(state)
    // No client yet, so the figures are only read.
    let state = poll_figures(state)
    actor.initialised(state) |> actor.returning(self) |> Ok
  }
  actor.new_with_initialiser(1000, initialise)
  |> actor.on_message(handle)
  |> actor.start
  |> result.map(fn(started) { started.data })
  |> result.replace_error("The deck owner did not start.")
}

/// The stylesheet from junkslides.toml, empty when the deck has none.
pub fn settings_css(owner: Subject(Message)) -> String {
  process.call(owner, 1000, SettingsCss)
}

fn path(config: Config, name: String) -> String {
  filepath.join(config.folder, name)
}

pub fn parse_deck(bytes: BitArray) -> Result(Deck, String) {
  use text <- result.try(
    bit_array.to_string(bytes)
    |> result.replace_error("deck.md is not valid UTF-8."),
  )
  file.parse(text, new_supply())
  |> result.map(fn(parsed) { parsed.0 })
  |> result.map_error(file.describe)
}

pub fn parse_layout(bytes: BitArray) -> Result(Layout, String) {
  bit_array.to_string(bytes)
  |> result.replace_error(Nil)
  |> result.try(fn(text) {
    file.parse_layout(text) |> result.replace_error(Nil)
  })
  |> result.replace_error(
    "layout.json is not valid. junkslides keeps its layout and does not write"
    <> " layout.json until the file is valid again.",
  )
}

fn read_theme(config: Config) -> #(List(String), List(String), String) {
  case store.read(path(config, "theme.css")) {
    Error(Nil) -> #([], [], store.missing)
    Ok(#(bytes, hash)) -> {
      let css = bit_array.to_string(bytes) |> result.unwrap("")
      #(contract.variants(css), contract.marks(css), hash)
    }
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
  let next = receive(state, message)
  // Whether the files are being written is a state the editor keeps on
  // screen, so every change of it is told, the end of it too.
  case unsaved(next) == unsaved(state) {
    True -> Nil
    False -> broadcast(next, protocol.Unsaved(unsaved(next)))
  }
  actor.continue(next)
}

/// The files that are not being written now, and why (06-runtime.md,
/// Writing files).
fn unsaved(state: State) -> List(#(String, String)) {
  let named = fn(name, reasons: List(Option(String))) {
    case option.values(reasons) {
      [reason, ..] -> [#(name, reason)]
      [] -> []
    }
  }
  list.append(
    named("deck.md", [state.deck_file.problem, state.deck_write]),
    named("layout.json", [state.layout_file.problem, state.layout_write]),
  )
}

fn receive(state: State, message: Message) -> State {
  case message {
    Join(client) -> {
      greet(state, client)
      State(..state, clients: [client, ..state.clients])
    }
    Leave(client) ->
      State(..state, clients: list.filter(state.clients, fn(c) { c != client }))
    FromClient(client, msg) -> from_client(state, client, msg)
    Poll -> {
      process.send_after(state.self, state.config.poll, Poll)
      state |> poll_files |> poll_theme |> poll_settings |> poll_figures
    }
    Flush(generation) if generation == state.generation ->
      state |> poll_files |> write_files |> retry_failed
    Flush(_) -> state
    Highlighted(blocks) -> {
      broadcast(state, protocol.Highlights(blocks))
      State(..state, highlights: blocks)
    }
    Exported(client, outcome) -> {
      send(client, protocol.Notice(exported_notice(outcome)))
      state
    }
    SettingsCss(reply) -> {
      process.send(reply, state.settings_file.css)
      state
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
      case
        session.apply(session_of(state), ops, supply, timestamp.system_time())
      {
        Error(error) ->
          reject(state, client, seq, protocol.describe_error(error))
        Ok(Session(deck:, layout:, history:)) -> {
          let pending = case state.pending {
            Groups(groups) -> Groups(list.append(groups, [Group(ops, supply)]))
            Replaced -> Replaced
          }
          State(..state, deck:, layout:, history:, pending:) |> changed
        }
      }
    }
    protocol.ApplyLayout(seq:, op:) ->
      case session.apply_layout(session_of(state), op) {
        Error(error) ->
          reject(state, client, seq, protocol.describe_error(error))
        Ok(Session(layout:, history:, ..)) ->
          State(..state, layout:, history:) |> changed
      }
    protocol.Undo -> step(state, client, session.undo(session_of(state)))
    protocol.Redo -> step(state, client, session.redo(session_of(state)))
    protocol.SaveView(view:) -> {
      case view.save(state.config.view_file, state.config.folder, view) {
        Ok(Nil) -> Nil
        Error(reason) ->
          send(client, protocol.Notice("Could not store the view: " <> reason))
      }
      State(..state, view:)
    }
    protocol.Export -> {
      // On its own process, so a slow tree-sitter never holds up the owner.
      let State(config:, deck:, layout:, self:, ..) = state
      process.spawn_unlinked(fn() {
        let outcome =
          export.write(
            folder: config.folder,
            out: export.default_out(config.folder),
            deck:,
            layout:,
            tree_sitter: config.tree_sitter,
          )
        process.send(self, Exported(client, outcome))
      })
      state
    }
    protocol.ExportPdf -> {
      // A browser takes seconds, so this too runs on its own process.
      let State(config:, deck:, layout:, self:, ..) = state
      send(client, protocol.Notice("Making a PDF..."))
      process.spawn_unlinked(fn() {
        let outcome =
          pdf.find()
          |> result.try(fn(browser) {
            export.write_pdf(
              folder: config.folder,
              out: export.default_out(config.folder),
              deck:,
              layout:,
              tree_sitter: config.tree_sitter,
              browser:,
            )
          })
        process.send(self, Exported(client, outcome))
      })
      state
    }
  }
}

/// The part of the state the pure session works on (`junkslides/session`).
fn session_of(state: State) -> Session {
  Session(state.deck, state.layout, state.history)
}

fn exported_notice(outcome: Result(export.Report, String)) -> String {
  case outcome {
    Error(problem) -> problem
    Ok(export.Report(page:, warnings: [])) -> "Exported to " <> page
    Ok(export.Report(page:, warnings:)) ->
      "Exported to " <> page <> ". " <> string.join(warnings, ". ")
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
  stepped: Option(Session),
) -> State {
  case stepped {
    None -> {
      send(client, state_msg(state))
      state
    }
    Some(Session(deck:, layout:, history:)) -> {
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
  state |> poll_figures |> schedule_flush
}

/// Reads the figures the deck names again. Clients get their text when what
/// can be drawn changes, and a notice for each figure that newly cannot.
fn poll_figures(state: State) -> State {
  let files =
    protocol.figures(state.deck)
    |> list.map(fn(url) {
      let last = list.key_find(state.figures, url)
      #(url, figures.read_again(state.config.folder, url, last))
    })
  case files == state.figures {
    True -> state
    False -> {
      let usable = figures.usable(files)
      case usable == figures.usable(state.figures) {
        True -> Nil
        False -> broadcast(state, protocol.Figures(usable))
      }
      let before =
        list.filter_map(state.figures, fn(pair) {
          figures.problem(pair.0, pair.1)
        })
      list.filter_map(files, fn(pair) { figures.problem(pair.0, pair.1) })
      |> list.filter(fn(problem) { !list.contains(before, problem) })
      |> list.each(fn(problem) { broadcast(state, protocol.Notice(problem)) })
      State(..state, figures: files)
    }
  }
}

/// Asks for the tokens of the deck's code blocks; the answer comes back as
/// `Highlighted`, so a slow command never holds up the owner.
fn request_highlights(state: State) -> Nil {
  case state.highlighter {
    Some(subject) ->
      process.send(
        subject,
        highlighter.Request(
          protocol.code_blocks(state.deck),
          state.settings_file.shading,
          fn(blocks) { process.send(state.self, Highlighted(blocks)) },
        ),
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
        "deck.md is missing. junkslides keeps the deck and does not write deck.md"
        <> " until the file is back."
      broadcast(state, protocol.Notice(problem))
      State(..state, deck_file: Disk(store.missing, Some(problem)))
    }
    Ok(#(bytes, hash)) ->
      case parse_deck(bytes) {
        Error(problem) -> {
          let problem =
            problem
            <> " junkslides keeps the last good state and does not write deck.md"
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
  "deck.md was edited outside junkslides while changes were not saved yet. Dropped "
  <> string.join(dropped, ", ")
  <> ", since the edit removed what they changed."
}

fn poll_layout(state: State) -> State {
  let layout_file = state.layout_file
  case store.read(path(state.config, "layout.json")) {
    Ok(#(_, hash)) if hash == layout_file.seen -> state
    Error(Nil) if layout_file.seen == store.missing -> state
    // junkslides owns layout.json: a deleted file is written again from the
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

/// junkslides.toml read again after an outside edit. A file that does not read
/// keeps the stylesheet of the last one that did, as deck.md and layout.json
/// keep their last good state.
fn poll_settings(state: State) -> State {
  let before = state.settings_file
  let seen = case store.read(path(state.config, settings_name)) {
    Ok(#(_, hash)) -> hash
    Error(Nil) -> store.missing
  }
  case seen == before.seen {
    True -> state
    False -> {
      let after = read_settings(state.config, before)
      case after.problem, before.problem {
        Some(problem), _ -> broadcast(state, protocol.Notice(problem))
        None, Some(_) ->
          broadcast(state, protocol.Notice(settings_name <> " reads again."))
        None, None -> Nil
      }
      case after.problem, after.missing == before.missing {
        None, False ->
          list.each(missing_notices(after), fn(notice) {
            broadcast(state, protocol.Notice(notice))
          })
        _, _ -> Nil
      }
      case after.css == before.css {
        True -> Nil
        False -> broadcast(state, protocol.ReloadTheme)
      }
      let state = State(..state, settings_file: after)
      case after.shading == before.shading {
        True -> Nil
        False -> request_highlights(state)
      }
      state
    }
  }
}

const settings_name = "junkslides.toml"

/// The settings file as it is on disk now, keeping the stylesheet of `last`
/// when it does not read.
fn read_settings(config: Config, last: SettingsFile) -> SettingsFile {
  case store.read(path(config, settings_name)) {
    Error(Nil) -> SettingsFile(store.missing, "", None, [], shade.default_rules)
    Ok(#(bytes, hash)) -> {
      let parsed =
        bit_array.to_string(bytes)
        |> result.replace_error(settings_name <> " is not valid UTF-8.")
        |> result.try(settings.parse)
      case parsed {
        Error(problem) ->
          SettingsFile(
            ..last,
            seen: hash,
            problem: Some(
              problem
              <> " junkslides keeps the settings it last read until the file is fixed.",
            ),
          )
        Ok(read) ->
          SettingsFile(
            seen: hash,
            css: settings.to_css(read, "/"),
            problem: None,
            missing: settings.files(read)
              |> list.filter(fn(file) {
                simplifile.is_file(path(config, file)) != Ok(True)
              }),
            shading: settings.shading(Some(read)),
          )
      }
    }
  }
}

fn missing_notices(file: SettingsFile) -> List(String) {
  case file.missing {
    [] -> []
    missing -> [
      settings_name
      <> " names files that are missing: "
      <> string.join(missing, ", ")
      <> ".",
    ]
  }
}

fn poll_theme(state: State) -> State {
  let #(variants, marks, seen) = read_theme(state.config)
  case seen == state.theme_seen {
    True -> state
    False -> {
      broadcast(state, protocol.ReloadTheme)
      let same = variants == state.variants && marks == state.marks
      let state = State(..state, variants:, marks:, theme_seen: seen)
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
    Some(_) -> State(..state, deck_write: None)
    None -> {
      let bytes = bit_array.from_string(file.print(state.deck))
      let saved =
        State(..state, base: state.deck, pending: Groups([]), deck_write: None)
      case store.hash(bytes) == state.deck_file.seen {
        True -> saved
        False ->
          case store.write_atomic(path(state.config, "deck.md"), bytes) {
            Ok(hash) -> State(..saved, deck_file: Disk(hash, None))
            Error(reason) ->
              write_failed(state, "deck.md", reason, fn(problem) {
                State(..state, deck_write: Some(problem))
              })
          }
      }
    }
  }
}

fn write_layout(state: State) -> State {
  case state.layout_file.problem {
    Some(_) -> State(..state, layout_write: None)
    None -> {
      let bytes = bit_array.from_string(file.print_layout(state.layout))
      case store.hash(bytes) == state.layout_file.seen {
        True -> State(..state, layout_write: None)
        False ->
          case store.write_atomic(path(state.config, "layout.json"), bytes) {
            Ok(hash) ->
              State(..state, layout_file: Disk(hash, None), layout_write: None)
            Error(reason) ->
              write_failed(state, "layout.json", reason, fn(problem) {
                State(..state, layout_write: Some(problem))
              })
          }
      }
    }
  }
}

/// How long after a failed write the next one is tried, in ms.
const retry = 1000

/// A write that failed is tried again by itself, so a disk that was full or
/// a folder that was locked for a moment needs no further edit to be
/// written. A change made meanwhile has its own flush and takes over.
fn retry_failed(state: State) -> State {
  case state.deck_write, state.layout_write {
    None, None -> Nil
    _, _ -> {
      process.send_after(state.self, retry, Flush(state.generation))
      Nil
    }
  }
  state
}

/// A write that failed is said once as a notice, and stays in `unsaved`
/// until a write of that file works.
fn write_failed(
  state: State,
  name: String,
  reason: String,
  keep: fn(String) -> State,
) -> State {
  let problem = "Could not write " <> name <> ": " <> reason
  let before = case name {
    "deck.md" -> state.deck_write
    _ -> state.layout_write
  }
  case before == Some(problem) {
    True -> Nil
    False -> broadcast(state, protocol.Notice(problem))
  }
  keep(problem)
}

// Sending -------------------------------------------------------------------

fn state_msg(state: State) -> ServerMsg {
  protocol.State(
    version: state.version,
    deck: state.deck,
    layout: state.layout,
    diagnostics: protocol.diagnostics(state.deck, state.marks),
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
  case figures.usable(state.figures) {
    [] -> Nil
    files -> send(client, protocol.Figures(files))
  }
  [
    state.deck_file.problem,
    state.layout_file.problem,
    state.settings_file.problem,
  ]
  |> option.values
  |> list.append(missing_notices(state.settings_file))
  |> list.append(
    list.filter_map(state.figures, fn(pair) { figures.problem(pair.0, pair.1) }),
  )
  |> list.each(fn(problem) { send(client, protocol.Notice(problem)) })
  case unsaved(state) {
    [] -> Nil
    files -> send(client, protocol.Unsaved(files))
  }
}

fn broadcast(state: State, msg: ServerMsg) -> Nil {
  list.each(state.clients, send(_, msg))
}

fn send(client: Subject(ServerMsg), msg: ServerMsg) -> Nil {
  process.send(client, msg)
}
