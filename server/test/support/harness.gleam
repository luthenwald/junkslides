//// A served copy of examples/talk with one WebSocket client, for the
//// integration tests. Each test uses its own folder and port.

import filepath
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/list
import gleam/result
import gleam/string
import simplifile
import stratus
import zeno/deck.{type Cell, type Deck}
import zeno/id.{type CellTag, type Id}
import zeno/layout.{type Layout}
import zeno/protocol.{type ClientMsg, type ServerMsg}
import zeno_server/state
import zeno_server/theme
import zeno_server/web

pub type Harness {
  Harness(
    folder: String,
    inbox: Subject(ServerMsg),
    socket: Subject(stratus.InternalMessage(ClientMsg)),
  )
}

const example = "../examples/talk"

/// A fresh copy of the example deck under build/scenarios/<name>, with its fonts.
pub fn folder(name: String) -> String {
  let assert Ok(cwd) = simplifile.current_directory()
  let folder = filepath.join(cwd, "build/scenarios/" <> name)
  let _ = simplifile.delete(folder)
  let assert Ok(Nil) = simplifile.create_directory_all(folder)
  list.each(["deck.md", "layout.json", "theme.css", "zeno.toml"], fn(name) {
    let assert Ok(Nil) =
      simplifile.copy_file(
        filepath.join(example, name),
        filepath.join(folder, name),
      )
  })
  let assert Ok(Nil) =
    simplifile.copy_directory(
      filepath.join(example, "fonts"),
      filepath.join(folder, "fonts"),
    )
  folder
}

/// Serves a folder and connects; the first message, the state, is left in
/// the inbox.
pub fn serve(folder: String, port: Int, debounce: Int) -> Harness {
  serve_with(folder, port, 30, debounce)
}

pub fn serve_with(
  folder: String,
  port: Int,
  poll: Int,
  debounce: Int,
) -> Harness {
  serve_config(
    state.Config(
      folder:,
      view_file: folder <> ".view.json",
      poll:,
      debounce:,
      tree_sitter: "zeno-no-such-command",
    ),
    port,
  )
}

pub fn serve_with_tree_sitter(
  folder: String,
  port: Int,
  command: String,
) -> Harness {
  let assert Ok(cwd) = simplifile.current_directory()
  serve_config(
    state.Config(
      folder:,
      view_file: folder <> ".view.json",
      poll: 50,
      debounce: 100,
      tree_sitter: filepath.join(cwd, command),
    ),
    port,
  )
}

fn serve_config(config: state.Config, port: Int) -> Harness {
  let folder = config.folder
  let assert Ok(owner) = state.start(config)
  let assert Ok(fonts) = theme.fonts_folder()
  let assert Ok(_) =
    web.start(web.Config(port:, folder:, client: folder, fonts:), owner)
  connect(folder, port)
}

pub fn start(name: String, port: Int) -> Harness {
  serve(folder(name), port, 100)
}

pub fn connect(folder: String, port: Int) -> Harness {
  let inbox = process.new_subject()
  let assert Ok(req) =
    request.to("http://127.0.0.1:" <> string.inspect(port) <> "/.zeno/ws")
  let assert Ok(client) =
    stratus.new(request: req, state: Nil)
    |> stratus.on_message(fn(state, message, conn) {
      case message {
        stratus.Text(text) -> {
          let assert Ok(msg) = protocol.decode_server(text)
          process.send(inbox, msg)
        }
        stratus.User(msg) -> {
          let assert Ok(Nil) =
            stratus.send_text_message(conn, protocol.encode_client(msg))
          Nil
        }
        _ -> Nil
      }
      stratus.continue(state)
    })
    |> stratus.start
  Harness(folder:, inbox:, socket: client.data)
}

pub fn send(harness: Harness, msg: ClientMsg) -> Nil {
  process.send(harness.socket, stratus.to_user_message(msg))
}

/// The next message other than highlights, within two seconds. Highlights
/// come whenever the highlighter answers (blocks without a grammar are
/// shaded too, D30), so tests that want them ask with `next_highlights`.
pub fn next(harness: Harness) -> ServerMsg {
  case next_any(harness) {
    protocol.Highlights(_) -> next(harness)
    msg -> msg
  }
}

/// The next message of any kind, within two seconds.
pub fn next_any(harness: Harness) -> ServerMsg {
  let assert Ok(msg) = process.receive(harness.inbox, 2000)
  msg
}

/// Skips messages up to the next state.
pub fn next_state(harness: Harness) -> #(Deck, Layout) {
  case next(harness) {
    protocol.State(deck:, layout:, ..) -> #(deck, layout)
    _ -> next_state(harness)
  }
}

/// Skips messages up to the next highlights.
pub fn next_highlights(harness: Harness) -> ServerMsg {
  case next_any(harness) {
    protocol.Highlights(_) as msg -> msg
    _ -> next_highlights(harness)
  }
}

/// Skips messages up to the next notice.
pub fn next_notice(harness: Harness) -> String {
  case next(harness) {
    protocol.Notice(text) -> text
    _ -> next_notice(harness)
  }
}

/// No message within `ms`.
pub fn quiet(harness: Harness, ms: Int) -> Bool {
  process.receive(harness.inbox, ms) == Error(Nil)
}

/// Replaces a file the way an editor that saves atomically would.
pub fn write(folder: String, name: String, contents: String) -> Nil {
  let path = filepath.join(folder, name)
  let assert Ok(Nil) = simplifile.write(path <> ".editor-tmp", contents)
  let assert Ok(Nil) = simplifile.rename(path <> ".editor-tmp", path)
  Nil
}

pub fn read(folder: String, name: String) -> String {
  let assert Ok(text) = simplifile.read(filepath.join(folder, name))
  text
}

/// Edits a file by replacing one exact piece of its text.
pub fn edit(folder: String, name: String, old: String, new: String) -> Nil {
  let text = read(folder, name)
  assert string.contains(text, old)
  write(folder, name, string.replace(text, old, new))
}

/// Waits up to three seconds for a condition on the folder.
pub fn eventually(check: fn() -> Bool) -> Bool {
  eventually_loop(check, 100)
}

fn eventually_loop(check: fn() -> Bool, tries: Int) -> Bool {
  case check(), tries {
    True, _ -> True
    False, 0 -> False
    False, _ -> {
      process.sleep(30)
      eventually_loop(check, tries - 1)
    }
  }
}

/// The example's IDs end in two hex digits.
pub fn example_id(suffix: String) -> Id(tag) {
  let assert Ok(id) = id.parse("019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e" <> suffix)
  id
}

pub fn find(deck: Deck, cell: Id(CellTag)) -> Result(Cell, Nil) {
  deck.find_cell(deck, cell) |> result.map(fn(location) { location.cell })
}
