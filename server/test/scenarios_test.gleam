//// The external edit scenarios of 08-roadmap.md, M2, numbered as there.
//// Each runs on a copy of examples/talk, edited the way an outside editor
//// would, while a client is connected over the WebSocket.

import gleam/dict
import gleam/erlang/process
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import junkslides/deck.{type Deck, Content, Position}
import junkslides/file
import junkslides/id
import junkslides/layout.{type Layout, Area, CellOrphan}
import junkslides/op
import junkslides/protocol
import support/harness.{example_id}

fn orphaned(layout: Layout, cell) -> Bool {
  list.any(layout.orphans, fn(orphan) {
    case orphan {
      CellOrphan(id:, ..) -> id == cell
      _ -> False
    }
  })
}

fn on_disk(h: harness.Harness, deck: Deck) -> Bool {
  harness.eventually(fn() {
    harness.read(h.folder, "deck.md") == file.print(deck)
  })
}

fn cell_block(suffix: String, body: String) -> String {
  "<!-- cell 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e" <> suffix <> " -->\n" <> body
}

const slide_two = "<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e05 -->\n\n"

/// 1. Edit a cell's text in an outside editor: same ID, layout kept.
pub fn s1_outside_text_edit_keeps_id_and_layout_test() {
  let h = harness.start("s1", 4881)
  let #(_, before) = harness.next_state(h)
  harness.edit(h.folder, "deck.md", "# Why lenses\n", "# Why lenses, again\n")
  let #(deck, layout) = harness.next_state(h)
  let assert Ok(cell) = harness.find(deck, example_id("02"))
  assert cell.source == "# Why lenses, again"
  assert layout == before
  assert harness.quiet(h, 300)
}

/// 2. Add a paragraph with no marker after a slide marker: new cell, flows.
pub fn s2_paragraph_without_marker_becomes_a_flowing_cell_test() {
  let h = harness.start("s2", 4882)
  let _ = harness.next_state(h)
  harness.edit(
    h.folder,
    "deck.md",
    slide_two,
    slide_two <> "A new paragraph.\n\n",
  )
  let #(deck, layout) = harness.next_state(h)
  let assert [_, slide, ..] = deck.slides
  let assert [new, image] = slide.cells
  assert new.source == "A new paragraph."
  assert image.id == example_id("06")
  assert dict.get(layout.cells, new.id) == Error(Nil)
  // The printer adds the marker; that write is not read back as an edit.
  assert on_disk(h, deck)
  assert string.contains(
    harness.read(h.folder, "deck.md"),
    "<!-- cell " <> id.to_string(new.id) <> " -->\nA new paragraph.",
  )
  assert harness.quiet(h, 300)
}

/// 3. Add a bare `---` line: new slide with a fresh ID; markers added on save.
pub fn s3_bare_break_becomes_a_slide_test() {
  let h = harness.start("s3", 4883)
  let #(before, _) = harness.next_state(h)
  harness.write(
    h.folder,
    "deck.md",
    harness.read(h.folder, "deck.md") <> "\n---\n\nNew slide.\n",
  )
  let #(deck, _) = harness.next_state(h)
  assert list.length(deck.slides) == list.length(before.slides) + 1
  let assert Ok(slide) = list.last(deck.slides)
  assert !list.contains(deck.slide_ids(before), slide.id)
  let assert [cell] = slide.cells
  assert cell.source == "New slide."
  assert on_disk(h, deck)
  assert string.contains(
    harness.read(h.folder, "deck.md"),
    "---\n<!-- slide " <> id.to_string(slide.id) <> " -->\n\n<!-- cell ",
  )
}

/// 4. Delete a cell: its record moves to orphans.
pub fn s4_deleted_cell_is_orphaned_test() {
  let h = harness.start("s4", 4884)
  let #(_, before) = harness.next_state(h)
  let title = example_id("02")
  let assert Ok(record) = dict.get(before.cells, title)
  harness.edit(h.folder, "deck.md", cell_block("02", "# Why lenses\n\n"), "")
  let #(deck, layout) = harness.next_state(h)
  assert harness.find(deck, title) == Error(Nil)
  assert dict.get(layout.cells, title) == Error(Nil)
  assert list.any(layout.orphans, fn(orphan) {
    case orphan {
      CellOrphan(id:, record: kept, ..) -> id == title && kept == record
      _ -> False
    }
  })
  assert harness.eventually(fn() {
    case file.parse_layout(harness.read(h.folder, "layout.json")) {
      Ok(written) -> orphaned(written, title)
      Error(_) -> False
    }
  })
}

/// 5. Cut a cell, save, paste it elsewhere, save: ID revived, layout restored.
pub fn s5_cut_and_paste_revives_the_record_test() {
  let h = harness.start("s5", 4885)
  let #(_, before) = harness.next_state(h)
  let image = example_id("06")
  let assert Ok(record) = dict.get(before.cells, image)
  let block = cell_block("06", "![A lens diagram](assets/lens.png)\n")
  harness.edit(h.folder, "deck.md", block <> "\n", "")
  let #(_, layout) = harness.next_state(h)
  assert orphaned(layout, image)
  harness.write(
    h.folder,
    "deck.md",
    harness.read(h.folder, "deck.md") <> "\n" <> block,
  )
  let #(deck, layout) = harness.next_state(h)
  let assert Ok(last) = list.last(deck.slides)
  assert list.map(last.cells, fn(c) { c.id }) == [image]
  assert dict.get(layout.cells, image) == Ok(record)
  assert !orphaned(layout, image)
}

/// 6. Copy a cell including its marker: the copy gets a fresh ID.
pub fn s6_copied_marker_gets_a_fresh_id_test() {
  let h = harness.start("s6", 4886)
  let #(_, before) = harness.next_state(h)
  let lens = example_id("03")
  let body =
    "A lens is a pair of functions, _get_ and _put_,\n"
    <> "satisfying a few round-trip laws.\n\n"
  harness.edit(
    h.folder,
    "deck.md",
    slide_two,
    slide_two <> cell_block("03", body),
  )
  let #(deck, layout) = harness.next_state(h)
  let assert [first, second, ..] = deck.slides
  let assert [_, original, _] = first.cells
  let assert [copy, _] = second.cells
  assert original.id == lens
  assert copy.id != lens
  assert copy.source == original.source
  assert dict.get(layout.cells, lens) == dict.get(before.cells, lens)
  assert dict.get(layout.cells, copy.id) == Error(Nil)
  assert on_disk(h, deck)
}

/// 7. Introduce a parse error: junkslides keeps state, shows the line, does not
/// write; fixing the error resumes normally.
pub fn s7_parse_error_keeps_state_and_does_not_write_test() {
  let h = harness.start("s7", 4887)
  let _ = harness.next_state(h)
  let good = harness.read(h.folder, "deck.md")
  let broken =
    string.replace(
      good,
      "round-trip laws.\n",
      "round-trip laws.\n<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e99 -->\n",
    )
  harness.write(h.folder, "deck.md", broken)
  let notice = harness.next_notice(h)
  assert string.contains(notice, "line 12")
  // That deck.md is not being written is a state, told apart from notices.
  assert harness.next_unsaved(h) == [#("deck.md", notice)]
  // Edits in junkslides go on, but deck.md is not written while it is broken.
  let laws = example_id("08")
  harness.send(h, protocol.Apply(1, [op.EditText(laws, "## The laws, kept")]))
  let #(deck, _) = harness.next_state(h)
  process.sleep(400)
  assert harness.read(h.folder, "deck.md") == broken
  // A client that connects now is told about the problem too.
  let late = harness.connect(h.folder, 4887)
  let _ = harness.next_state(late)
  assert string.contains(harness.next_notice(late), "line 12")
  assert harness.next_unsaved(late) == [#("deck.md", notice)]
  // Fixing the file resumes, and the edit made meanwhile is kept.
  harness.write(h.folder, "deck.md", good)
  assert harness.next_notice(h) == "deck.md reads again."
  assert harness.next_unsaved(h) == []
  assert on_disk(h, deck)
  assert string.contains(harness.read(h.folder, "deck.md"), "## The laws, kept")
}

/// 8. Edit while a junkslides write is pending: pending ops are rebased; ops on
/// removed cells are dropped with a notice.
pub fn s8_pending_ops_are_rebased_onto_an_outside_edit_test() {
  let h = harness.serve(harness.folder("s8"), 4888, 1000)
  let _ = harness.next_state(h)
  let original = harness.read(h.folder, "deck.md")
  let #(lens, laws, gleam) = #(
    example_id("03"),
    example_id("08"),
    example_id("0d"),
  )
  harness.send(
    h,
    protocol.Apply(1, [op.EditText(lens, "Changed in junkslides.")]),
  )
  let _ = harness.next_state(h)
  harness.send(h, protocol.Apply(2, [op.EditText(gleam, "### In Gleam!")]))
  let _ = harness.next_state(h)
  harness.send(
    h,
    protocol.Apply(3, [op.Insert(Position(example_id("14"), 0), Content)]),
  )
  let #(deck, _) = harness.next_state(h)
  let assert Ok(last) = list.last(deck.slides)
  let assert [new] = last.cells
  let area = Area(x: 60, y: 60, w: 240, h: 240)
  harness.send(h, protocol.ApplyLayout(4, layout.Place(new.id, area)))
  let _ = harness.next_state(h)
  // Nothing written yet; now the outside edit.
  assert harness.read(h.folder, "deck.md") == original
  harness.edit(h.folder, "deck.md", "## The laws\n", "## The three laws\n")
  harness.edit(h.folder, "deck.md", cell_block("0d", "### In Gleam\n\n"), "")
  let notice = harness.next_notice(h)
  assert string.contains(notice, "Dropped a text edit (unknown cell)")
  let #(deck, layout) = harness.next_state(h)
  let source = fn(cell) {
    let assert Ok(cell) = harness.find(deck, cell)
    cell.source
  }
  assert source(lens) == "Changed in junkslides."
  assert source(laws) == "## The three laws"
  assert harness.find(deck, gleam) == Error(Nil)
  // The inserted cell is replayed with the same ID, so its placement holds.
  assert source(new.id) == ""
  let assert Ok(record) = dict.get(layout.cells, new.id)
  assert record.place == Some(area)
  assert on_disk(h, deck)
}

/// 9. Corrupt layout.json: junkslides keeps its layout and reports it.
pub fn s9_corrupt_layout_is_kept_and_reported_test() {
  let h = harness.start("s9", 4889)
  let _ = harness.next_state(h)
  let good = harness.read(h.folder, "layout.json")
  harness.write(h.folder, "layout.json", "{ not json")
  assert string.contains(harness.next_notice(h), "layout.json is not valid")
  let lens = example_id("03")
  harness.send(
    h,
    protocol.ApplyLayout(1, layout.SetVariant(lens, Some("large"))),
  )
  let #(_, layout) = harness.next_state(h)
  let assert Ok(record) = dict.get(layout.cells, lens)
  assert record.variant == Some("large")
  process.sleep(400)
  assert harness.read(h.folder, "layout.json") == "{ not json"
  // A valid file replaces the layout as one step.
  harness.write(h.folder, "layout.json", good)
  assert harness.next_notice(h) == "layout.json reads again."
  let #(_, layout) = harness.next_state(h)
  let assert Ok(record) = dict.get(layout.cells, lens)
  assert record.variant == Some("quiet")
}

/// 10. Kill the server between the deck.md and layout.json writes: on
/// restart the consistency step repairs the layout. The folder is left as
/// that crash would leave it: deck.md without one cell and with an orphan
/// back, layout.json as before.
pub fn s10_restart_repairs_a_stale_layout_test() {
  let folder = harness.folder("s10")
  harness.edit(folder, "deck.md", cell_block("02", "# Why lenses\n\n"), "")
  harness.write(
    folder,
    "deck.md",
    harness.read(folder, "deck.md") <> "\n" <> cell_block("70", "Back again.\n"),
  )
  let h = harness.serve(folder, 4890, 100)
  let #(deck, layout) = harness.next_state(h)
  let #(title, back) = #(example_id("02"), example_id("70"))
  assert harness.find(deck, title) == Error(Nil)
  assert orphaned(layout, title)
  assert dict.get(layout.cells, back)
    == Ok(layout.CellRecord(option.None, Some("large"), option.None))
  assert !orphaned(layout, back)
  assert harness.eventually(fn() {
    case file.parse_layout(harness.read(h.folder, "layout.json")) {
      Ok(written) ->
        orphaned(written, title) && result.is_ok(dict.get(written.cells, back))
      Error(_) -> False
    }
  })
}

/// 8, the other order: the write is due before polling has seen the outside
/// edit. The flush reads the file first, so the edit is rebased, not lost.
pub fn s8_flush_reads_the_file_before_writing_test() {
  let h = harness.serve_with(harness.folder("s8-flush"), 4897, 60_000, 150)
  let _ = harness.next_state(h)
  let lens = example_id("03")
  harness.send(
    h,
    protocol.Apply(1, [op.EditText(lens, "Changed in junkslides.")]),
  )
  let _ = harness.next_state(h)
  harness.edit(h.folder, "deck.md", "## The laws\n", "## The three laws\n")
  let #(deck, _) = harness.next_state(h)
  let assert Ok(laws) = harness.find(deck, example_id("08"))
  assert laws.source == "## The three laws"
  let assert Ok(cell) = harness.find(deck, lens)
  assert cell.source == "Changed in junkslides."
  assert on_disk(h, deck)
}
