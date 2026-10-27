//// The cells pane in headless Chrome (D18) against a real server, each test
//// on its own copy of examples/talk. Run with `just e2e`, which builds the
//// client and starts Chrome on port 9334.

import cdp.{type Page}
import filepath
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/result
import gleam/string
import simplifile
import zeno/protocol
import zeno_server/state
import zeno_server/view
import zeno_server/web

const chrome = 9334

pub fn loads_the_deck_test() {
  let #(page, _) = open("load", 4901)
  assert cells(page) == 14
  // The last slide has no cells; it is shown as a place to select.
  assert cdp.count(page, ".ze-empty") == 1
  assert cdp.count(page, ".ze-slide") == 6
  assert cdp.count(page, ".ze-notes") == 2
  assert selected(page) == cell("02")
  assert string.contains(status(page), "command")
  assert string.contains(status(page), "01/06")
}

pub fn keys_move_the_selection_test() {
  let #(page, _) = open("navigate", 4902)
  press(page, "j")
  assert selected(page) == cell("03")
  // From the notes of slide 1 to the first cell of slide 2.
  press(page, "j")
  press(page, "j")
  assert selected(page) == cell("06")
  assert string.contains(status(page), "02/06")
  press(page, "}")
  assert selected(page) == cell("08")
  press(page, "{")
  press(page, "{")
  assert selected(page) == cell("02")
  press(page, "k")
  assert selected(page) == cell("02")
}

pub fn typing_reaches_the_file_test() {
  let #(page, folder) = open("type", 4903)
  press(page, "j")
  press(page, "Enter")
  assert string.contains(status(page), "edit")
  // Focus leaves the cursor at the end of the text.
  let assert Ok(_) = cdp.type_text(page, " Optics.")
  // Sent while typing, before the commit.
  assert eventually(fn() {
    string.contains(deck(folder), "round-trip laws. Optics.\n")
  })
  press(page, "Escape")
  assert string.contains(status(page), "command")
  assert selected(page) == cell("03")
}

pub fn new_cell_with_a_break_starts_a_slide_test() {
  let #(page, folder) = open("new", 4904)
  press(page, "o")
  assert eventually(fn() { cdp.count(page, ".ze-editing") == 1 })
  assert cells(page) == 15
  let assert Ok(_) = cdp.type_text(page, "Fresh\n---\nAfter")
  // The break waits for the commit.
  process.sleep(400)
  assert cdp.count(page, ".ze-slide") == 6
  press(page, "Escape")
  assert eventually(fn() { cdp.count(page, ".ze-slide") == 7 })
  assert eventually(fn() {
    let text = deck(folder)
    string.contains(text, "# Why lenses")
    && string.contains(text, "Fresh\n\n---")
    && string.contains(text, "After")
  })
}

pub fn cut_and_paste_keep_the_cell_id_test() {
  let #(page, folder) = open("cut", 4905)
  press(page, "d")
  assert eventually(fn() { cells(page) == 13 })
  assert selected(page) == cell("03")
  assert eventually(fn() { !string.contains(deck(folder), "# Why lenses") })
  press(page, "p")
  assert eventually(fn() { cells(page) == 14 })
  // Pasted below, with its old ID: the cell is revived, not new.
  assert selected(page) == cell("02")
  assert eventually(fn() {
    string.contains(
      deck(folder),
      "satisfying a few round-trip laws.\n\n<!-- cell " <> cell("02"),
    )
  })
}

pub fn move_and_undo_test() {
  let #(page, folder) = open("move", 4906)
  let original = deck(folder)
  press(page, "J")
  assert eventually(fn() {
    string.contains(
      deck(folder),
      "round-trip laws.\n\n<!-- cell " <> cell("02"),
    )
  })
  assert selected(page) == cell("02")
  press(page, "u")
  assert eventually(fn() { deck(folder) == original })
  press(page, "U")
  assert eventually(fn() { deck(folder) != original })
}

pub fn restructuring_keys_test() {
  let #(page, folder) = open("restructure", 4912)
  let has = fn(text) {
    eventually(fn() { string.contains(deck(folder), text) })
  }
  press(page, "t")
  assert has("<!-- notes " <> cell("02"))
  press(page, "t")
  assert has("<!-- cell " <> cell("02"))
  // A new slide starting at the second cell, then joined again.
  press(page, "j")
  press(page, "b")
  assert eventually(fn() { cdp.count(page, ".ze-slide") == 7 })
  assert has("# Why lenses\n\n---\n<!-- slide ")
  press(page, "B")
  assert eventually(fn() { cdp.count(page, ".ze-slide") == 6 })
  press(page, "k")
  press(page, "m")
  assert eventually(fn() { cells(page) == 13 })
  assert has("# Why lenses\n\nA lens is")
  press(page, "D")
  assert eventually(fn() { cells(page) == 14 })
  assert selected(page) != cell("02")
  assert eventually(fn() {
    list.length(string.split(deck(folder), "# Why lenses")) == 3
  })
}

pub fn marker_line_is_shown_and_can_be_dropped_test() {
  let #(page, folder) = open("marker", 4907)
  let original = deck(folder)
  press(page, "i")
  let assert Ok(_) = cdp.type_text(page, "\n<!-- cell -->\n")
  assert eventually(fn() { string.contains(problem(page), "marker line") })
  press(page, "Escape")
  assert string.contains(status(page), "edit")
  assert string.contains(status(page), "Esc twice")
  press(page, "Escape")
  assert string.contains(status(page), "command")
  assert cdp.count(page, ".ze-problem") == 0
  assert deck(folder) == original
}

pub fn split_at_the_cursor_test() {
  let #(page, folder) = open("split", 4908)
  press(page, "Enter")
  // From the end of `# Why lenses` to just before `lenses`.
  list.each(list.repeat("ArrowLeft", 6), press(page, _))
  key(page, "Enter", [cdp.Alt])
  assert eventually(fn() { cells(page) == 15 })
  // Edit mode continues in the new cell, which has the rest of the text.
  assert eventually(fn() { cdp.count(page, ".ze-editing") == 1 })
  assert selected(page) != cell("02")
  press(page, "Escape")
  assert eventually(fn() {
    let text = deck(folder)
    string.contains(text, cell("02") <> " -->\n# Why \n\n<!-- cell ")
    && string.contains(text, " -->\nlenses\n")
  })
}

pub fn panes_hide_and_the_view_is_saved_test() {
  let #(page, folder) = open("hide", 4909)
  key(page, "[", [cdp.Ctrl])
  assert eventually(fn() { cdp.count(page, ".ze-cells-pane") == 0 })
  assert eventually(fn() { saved_view(folder).cells_hidden })
  // Hiding the other pane shows this one again: never both hidden.
  key(page, "]", [cdp.Ctrl])
  assert eventually(fn() { cdp.count(page, ".ze-slide-pane") == 0 })
  assert cdp.count(page, ".ze-cells-pane") == 1
  assert eventually(fn() {
    saved_view(folder) == protocol.View(40, False, True)
  })
  key(page, "]", [cdp.Ctrl])
  assert eventually(fn() { cdp.count(page, ".ze-slide-pane") == 1 })
}

pub fn a_view_with_both_panes_hidden_shows_the_cells_test() {
  let folder = prepare("both-hidden")
  let assert Ok(Nil) =
    view.save(folder <> ".view.json", folder, protocol.View(40, True, True))
  let #(page, _, _, _) = open_folder(folder, 4914)
  assert cdp.count(page, ".ze-cells-pane") == 1
  assert cdp.count(page, ".ze-slide-pane") == 0
}

pub fn divider_drags_and_is_saved_test() {
  let #(page, folder) = open("divider", 4910)
  let assert Ok(b) = cdp.box(page, ".ze-divider")
  let y = b.y +. 100.0
  let assert Ok(_) = cdp.mouse(page, cdp.Press, b.x +. 2.0, y)
  list.each([550, 650, 750, 770], fn(x) {
    let assert Ok(_) = cdp.mouse(page, cdp.Move, int.to_float(x), y)
  })
  let assert Ok(_) = cdp.mouse(page, cdp.Release, 770.0, y)
  // 770 of 1280 pixels is in the strip for 60 percent.
  assert eventually(fn() { saved_view(folder).cells_width == 60 })
  let assert Ok(pane) = cdp.box(page, ".ze-cells-pane")
  assert int.absolute_value(cdp.round(pane.w) - 768) <= 2
}

pub fn outside_edits_appear_test() {
  let #(page, folder) = open("outside", 4911)
  let path = filepath.join(folder, "deck.md")
  let assert Ok(text) = simplifile.read(path)
  let assert Ok(Nil) =
    simplifile.write(path, string.replace(text, "# Why lenses", "# Why optics"))
  assert eventually(fn() {
    cdp.attribute(page, ".ze-selected .ze-grow", "data-value")
    == Ok("# Why optics")
  })
}

pub fn offline_edit_waits_for_the_connection_test() {
  let #(page, folder, owner, web) = open_with("offline", 4913)
  press(page, "Enter")
  let assert Ok(_) = cdp.type_text(page, " Kept.")
  // The server goes away; the owner of the deck stays.
  process.unlink(web.pid)
  process.kill(web.pid)
  assert eventually(fn() { string.contains(status(page), "offline") })
  press(page, "Escape")
  assert string.contains(status(page), "edit")
  assert string.contains(status(page), "Not connected")
  let assert Ok(_) = serve(folder, 4913, owner)
  assert eventually(fn() { !string.contains(status(page), "offline") })
  press(page, "Escape")
  assert string.contains(status(page), "command")
  assert eventually(fn() { string.contains(deck(folder), "# Why lenses Kept.") })
}

// Helpers ----------------------------------------------------------------------

/// Serves a fresh copy of the example deck and opens the editor on it.
fn open(name: String, port: Int) -> #(Page, String) {
  let #(page, folder, _, _) = open_with(name, port)
  #(page, folder)
}

fn open_with(
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

/// A fresh copy of the example deck, without view state.
fn prepare(name: String) -> String {
  let assert Ok(cwd) = simplifile.current_directory()
  let folder = filepath.join(cwd, "build/scenarios/" <> name)
  let _ = simplifile.delete(folder)
  let _ = simplifile.delete(folder <> ".view.json")
  let assert Ok(Nil) = simplifile.create_directory_all(folder)
  list.each(["deck.md", "layout.json", "theme.css"], fn(file) {
    let assert Ok(Nil) =
      simplifile.copy_file(
        filepath.join("../examples/talk", file),
        filepath.join(folder, file),
      )
  })
  folder
}

fn open_folder(
  folder: String,
  port: Int,
) -> #(
  Page,
  String,
  Subject(state.Message),
  actor.Started(static_supervisor.Supervisor),
) {
  let config =
    state.Config(
      folder:,
      view_file: folder <> ".view.json",
      poll: 50,
      debounce: 100,
    )
  let assert Ok(owner) = state.start(config)
  let assert Ok(web) = serve(folder, port, owner)
  let assert Ok(page) = cdp.connect(chrome)
  let assert Ok(_) = cdp.viewport(page, 1280, 800)
  let url = "http://127.0.0.1:" <> int.to_string(port) <> "/"
  let assert Ok(_) = cdp.open(page, url, ".ze-selected")
  #(page, folder, owner, web)
}

fn serve(folder: String, port: Int, owner: Subject(state.Message)) {
  let assert Ok(cwd) = simplifile.current_directory()
  let client = filepath.join(cwd, "../server/priv/static")
  web.start(web.Config(port:, folder:, client:), owner)
}

fn press(page: Page, name: String) -> Nil {
  key(page, name, [])
}

fn key(page: Page, name: String, modifiers: List(cdp.Modifier)) -> Nil {
  let assert Ok(_) = cdp.key(page, name, modifiers)
  Nil
}

fn selected(page: Page) -> String {
  cdp.attribute(page, ".ze-selected", "data-cell") |> result.unwrap("")
}

fn cells(page: Page) -> Int {
  cdp.count(page, ".ze-cell:not(.ze-empty)")
}

fn status(page: Page) -> String {
  cdp.html(page, ".ze-status") |> result.unwrap("")
}

fn problem(page: Page) -> String {
  cdp.html(page, ".ze-problem") |> result.unwrap("")
}

fn deck(folder: String) -> String {
  let assert Ok(text) = simplifile.read(filepath.join(folder, "deck.md"))
  text
}

fn saved_view(folder: String) -> protocol.View {
  view.load(folder <> ".view.json", folder)
}

fn cell(suffix: String) -> String {
  "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e" <> suffix
}

fn eventually(check: fn() -> Bool) -> Bool {
  cdp.wait(3000, check) == Ok(Nil)
}
