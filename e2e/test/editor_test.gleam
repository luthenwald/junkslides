//// The cells pane in headless Chrome (D18) against a real server, each test
//// on its own copy of examples/talk. Run with `just e2e`, which builds the
//// client and starts Chrome on port 9334.

import cdp
import filepath
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/string
import harness.{
  cell, cells, deck, eventually, key, open, open_folder, open_with, prepare,
  press, problem, saved_view, selected, serve, status,
}
import junkslides/protocol
import junkslides_server/view
import simplifile

/// The editor's source text is in Victor Mono from the fonts that come with junkslides, even when
/// the theme names no font and the deck has none.
pub fn the_source_text_has_the_editors_own_mono_test() {
  let folder = prepare("editor-mono")
  let assert Ok(Nil) = simplifile.delete(filepath.join(folder, "fonts"))
  let assert Ok(Nil) =
    simplifile.write(
      filepath.join(folder, "theme.css"),
      ".js-slide { color: #000; }\n",
    )
  let #(page, _, _, _) = open_folder(folder, 4951)
  press(page, "Enter")
  assert eventually(fn() {
    case cdp.loaded_fonts(page) {
      Ok(fonts) -> string.contains(fonts, "Victor Mono normal")
      Error(_) -> False
    }
  })
}

pub fn loads_the_deck_test() {
  let #(page, _) = open("load", 4901)
  assert cells(page) == 16
  // The last slide has no cells; it is shown as a place to select.
  assert cdp.count(page, ".jse-empty") == 1
  assert cdp.count(page, ".jse-slide") == 7
  assert cdp.count(page, ".jse-notes") == 2
  assert selected(page) == cell("02")
  assert string.contains(status(page), "command")
  assert string.contains(status(page), "01/07")
}

pub fn keys_move_the_selection_test() {
  let #(page, _) = open("navigate", 4902)
  press(page, "j")
  assert selected(page) == cell("03")
  // From the notes of slide 1 to the first cell of slide 2.
  press(page, "j")
  press(page, "j")
  assert selected(page) == cell("06")
  assert string.contains(status(page), "02/07")
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
  assert eventually(fn() { cdp.count(page, ".jse-editing") == 1 })
  assert cells(page) == 17
  let assert Ok(_) = cdp.type_text(page, "Fresh\n---\nAfter")
  // The break waits for the commit.
  process.sleep(400)
  assert cdp.count(page, ".jse-slide") == 7
  press(page, "Escape")
  assert eventually(fn() { cdp.count(page, ".jse-slide") == 8 })
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
  assert eventually(fn() { cells(page) == 15 })
  assert selected(page) == cell("03")
  assert eventually(fn() { !string.contains(deck(folder), "# Why lenses") })
  press(page, "p")
  assert eventually(fn() { cells(page) == 16 })
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

pub fn purge_removes_orphans_and_undo_brings_them_back_test() {
  let #(page, folder) = open("purge", 4915)
  let orphans = fn() { string.contains(layout(folder), "\"retired_at\"") }
  assert string.contains(status(page), "1 orphan")
  press(page, "X")
  assert eventually(fn() { !orphans() })
  assert string.contains(status(page), "Removed 1 orphan; u brings it back.")
  let counted = fn() {
    status(page)
    |> string.replace("Removed 1 orphan", "")
    |> string.contains("1 orphan")
  }
  assert eventually(fn() { !counted() })
  press(page, "u")
  assert eventually(orphans)
  press(page, "X")
  press(page, "X")
  assert eventually(fn() {
    string.contains(status(page), "There are no orphans.")
  })
}

fn layout(folder: String) -> String {
  let assert Ok(text) = simplifile.read(filepath.join(folder, "layout.json"))
  text
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
  assert eventually(fn() { cdp.count(page, ".jse-slide") == 8 })
  assert has("# Why lenses\n\n---\n<!-- slide ")
  press(page, "B")
  assert eventually(fn() { cdp.count(page, ".jse-slide") == 7 })
  press(page, "k")
  press(page, "m")
  assert eventually(fn() { cells(page) == 15 })
  assert has("# Why lenses\n\nA lens is")
  press(page, "D")
  assert eventually(fn() { cells(page) == 16 })
  assert selected(page) != cell("02")
  assert eventually(fn() {
    list.length(string.split(deck(folder), "# Why lenses")) == 3
  })
}

pub fn cut_on_an_empty_slide_deletes_it_test() {
  let #(page, folder) = open("empty-slide", 4937)
  let original = deck(folder)
  list.each(list.repeat("}", 6), press(page, _))
  assert eventually(fn() { string.contains(status(page), "07/07") })
  press(page, "d")
  assert eventually(fn() { cdp.count(page, ".jse-slide") == 6 })
  assert cdp.count(page, ".jse-empty") == 0
  assert eventually(fn() { !string.contains(deck(folder), cell("14")) })
  // The end of the slide before it is selected.
  assert selected(page) == cell("17")
  press(page, "u")
  assert eventually(fn() { deck(folder) == original })
}

pub fn ctrl_shift_d_deletes_a_slide_with_its_cells_test() {
  let #(page, folder) = open("delete-slide", 4938)
  let original = deck(folder)
  key(page, "D", [cdp.Ctrl, cdp.Shift])
  assert eventually(fn() { cdp.count(page, ".jse-slide") == 6 })
  assert cells(page) == 13
  assert string.contains(
    status(page),
    "Deleted the slide and its 3 cells; u brings them back.",
  )
  assert eventually(fn() { !string.contains(deck(folder), "# Why lenses") })
  assert selected(page) == cell("06")
  press(page, "u")
  assert eventually(fn() { deck(folder) == original })
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
  assert cdp.count(page, ".jse-problem") == 0
  assert deck(folder) == original
}

pub fn split_at_the_cursor_test() {
  let #(page, folder) = open("split", 4908)
  press(page, "Enter")
  // From the end of `# Why lenses` to just before `lenses`.
  list.each(list.repeat("ArrowLeft", 6), press(page, _))
  key(page, "Enter", [cdp.Alt])
  assert eventually(fn() { cells(page) == 17 })
  // Edit mode continues in the new cell, which has the rest of the text.
  assert eventually(fn() { cdp.count(page, ".jse-editing") == 1 })
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
  assert eventually(fn() { cdp.count(page, ".jse-cells-pane") == 0 })
  assert eventually(fn() { saved_view(folder).cells_hidden })
  // Hiding the other pane shows this one again: never both hidden.
  key(page, "]", [cdp.Ctrl])
  assert eventually(fn() { cdp.count(page, ".jse-slide-pane") == 0 })
  assert cdp.count(page, ".jse-cells-pane") == 1
  assert eventually(fn() {
    saved_view(folder) == protocol.View(40, False, True, 30)
  })
  key(page, "]", [cdp.Ctrl])
  assert eventually(fn() { cdp.count(page, ".jse-slide-pane") == 1 })
}

pub fn a_view_with_both_panes_hidden_shows_the_cells_test() {
  let folder = prepare("both-hidden")
  let assert Ok(Nil) =
    view.save(folder <> ".view.json", folder, protocol.View(40, True, True, 30))
  let #(page, _, _, _) = open_folder(folder, 4914)
  assert cdp.count(page, ".jse-cells-pane") == 1
  assert cdp.count(page, ".jse-slide-pane") == 0
}

pub fn divider_drags_and_is_saved_test() {
  let #(page, folder) = open("divider", 4910)
  let assert Ok(b) = cdp.box(page, ".jse-divider")
  let y = b.y +. 100.0
  let assert Ok(_) = cdp.mouse(page, cdp.Press, b.x +. 2.0, y)
  list.each([550, 650, 750, 770], fn(x) {
    let assert Ok(_) = cdp.mouse(page, cdp.Move, int.to_float(x), y)
  })
  let assert Ok(_) = cdp.mouse(page, cdp.Release, 770.0, y)
  // 770 of 1280 pixels is in the strip for 60 percent.
  assert eventually(fn() { saved_view(folder).cells_width == 60 })
  let assert Ok(pane) = cdp.box(page, ".jse-cells-pane")
  assert int.absolute_value(cdp.round(pane.w) - 768) <= 2
}

pub fn outside_edits_appear_test() {
  let #(page, folder) = open("outside", 4911)
  let path = filepath.join(folder, "deck.md")
  let assert Ok(text) = simplifile.read(path)
  let assert Ok(Nil) =
    simplifile.write(path, string.replace(text, "# Why lenses", "# Why optics"))
  assert eventually(fn() {
    cdp.attribute(page, ".jse-selected .jse-grow", "data-value")
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
