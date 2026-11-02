//// Shared by the browser checks: a fresh copy of examples/talk served in
//// process, a page in headless Chrome (D18) on port 9334, and small
//// readers for the page and the files on disk.

import cdp.{type Page}
import filepath
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/result
import simplifile
import zeno/file
import zeno/id
import zeno/layout
import zeno/protocol
import zeno_server/state
import zeno_server/view
import zeno_server/web

const chrome = 9334

/// Serves a fresh copy of the example deck and opens the editor on it.
pub fn open(name: String, port: Int) -> #(Page, String) {
  let #(page, folder, _, _) = open_with(name, port)
  #(page, folder)
}

pub fn open_with(
  name: String,
  port: Int,
) -> #(
  Page,
  String,
  Subject(state.Message),
  actor.Started(static_supervisor.Supervisor),
) {
  open_folder(prepare(name), port)
}

/// A fresh copy of the example deck with its fonts, without view state.
pub fn prepare(name: String) -> String {
  let assert Ok(cwd) = simplifile.current_directory()
  let folder = filepath.join(cwd, "build/scenarios/" <> name)
  let _ = simplifile.delete(folder)
  let _ = simplifile.delete(folder <> ".view.json")
  let assert Ok(Nil) = simplifile.create_directory_all(folder)
  list.each(["deck.md", "layout.json", "theme.css", "zeno.toml"], fn(file) {
    let assert Ok(Nil) =
      simplifile.copy_file(
        filepath.join("../examples/talk", file),
        filepath.join(folder, file),
      )
  })
  let assert Ok(Nil) =
    simplifile.copy_directory(
      "../examples/talk/fonts",
      filepath.join(folder, "fonts"),
    )
  folder
}

pub fn open_folder(
  folder: String,
  port: Int,
) -> #(
  Page,
  String,
  Subject(state.Message),
  actor.Started(static_supervisor.Supervisor),
) {
  let assert Ok(cwd) = simplifile.current_directory()
  let config =
    state.Config(
      folder:,
      view_file: folder <> ".view.json",
      poll: 50,
      debounce: 100,
      tree_sitter: filepath.join(
        cwd,
        "../server/test/fixtures/fake-tree-sitter",
      ),
    )
  let assert Ok(owner) = state.start(config)
  let assert Ok(web) = serve(folder, port, owner)
  let assert Ok(page) = cdp.connect(chrome)
  let assert Ok(_) = cdp.viewport(page, 1280, 800)
  let url = "http://127.0.0.1:" <> int.to_string(port) <> "/"
  let assert Ok(_) = cdp.open(page, url, ".ze-selected")
  #(page, folder, owner, web)
}

pub fn serve(folder: String, port: Int, owner: Subject(state.Message)) {
  let assert Ok(cwd) = simplifile.current_directory()
  let client = filepath.join(cwd, "../server/priv/static")
  let fonts = filepath.join(cwd, "../server/priv/fonts")
  web.start(web.Config(port:, folder:, client:, fonts:), owner)
}

pub fn press(page: Page, name: String) -> Nil {
  key(page, name, [])
}

pub fn key(page: Page, name: String, modifiers: List(cdp.Modifier)) -> Nil {
  let assert Ok(_) = cdp.key(page, name, modifiers)
  Nil
}

pub fn selected(page: Page) -> String {
  cdp.attribute(page, ".ze-selected", "data-cell") |> result.unwrap("")
}

pub fn cells(page: Page) -> Int {
  cdp.count(page, ".ze-cell:not(.ze-empty)")
}

pub fn status(page: Page) -> String {
  cdp.html(page, ".ze-status") |> result.unwrap("")
}

pub fn problem(page: Page) -> String {
  cdp.html(page, ".ze-problem") |> result.unwrap("")
}

pub fn deck(folder: String) -> String {
  let assert Ok(text) = simplifile.read(filepath.join(folder, "deck.md"))
  text
}

pub fn saved_view(folder: String) -> protocol.View {
  view.load(folder <> ".view.json", folder)
}

pub fn cell(suffix: String) -> String {
  "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e" <> suffix
}

pub fn eventually(check: fn() -> Bool) -> Bool {
  cdp.wait(3000, check) == Ok(Nil)
}

/// The layout record of a cell, as layout.json on disk has it.
pub fn record(folder: String, suffix: String) -> layout.CellRecord {
  let assert Ok(text) = simplifile.read(filepath.join(folder, "layout.json"))
  let assert Ok(saved) = file.parse_layout(text)
  let assert Ok(cell) = id.parse(cell(suffix))
  layout.record(saved, cell)
}
