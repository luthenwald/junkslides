import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import simplifile
import zeno/deck.{type Deck, Cell, Content, Deck, Notes, Slide}
import zeno/dialect
import zeno/file.{
  MisplacedHeader, ParseError, SlideMarkerWithoutBreak, UnknownVersion,
}
import zeno/id
import zeno/layout
import zeno/line

const example = "../examples/talk/deck.md"

fn parse(text: String) -> Deck {
  let assert Ok(#(deck, _)) = file.parse(text, id.test_supply(1))
  deck
}

fn sources(deck: Deck) -> List(List(String)) {
  list.map(deck.slides, fn(slide) {
    list.map(slide.cells, fn(cell) { cell.source })
  })
}

pub fn example_round_trips_byte_for_byte_test() {
  let assert Ok(text) = simplifile.read(example)
  let deck = parse(text)
  assert file.print(deck) == text
  assert deck.violations(deck) == []
  assert list.length(deck.slides) == 6
  // The fourth slide holds an empty cell; the last slide is empty.
  let assert Ok(fourth) = list.drop(deck.slides, 3) |> list.first
  let assert Ok(empty) = list.last(fourth.cells)
  assert empty.source == ""
  let assert Ok(last) = list.last(deck.slides)
  assert last.cells == []
}

pub fn example_has_every_allowed_construct_without_problems_test() {
  let assert Ok(text) = simplifile.read(example)
  let deck = parse(text)
  let all =
    deck.cells(deck) |> list.map(fn(c) { c.source }) |> string.join("\n")
  list.each(
    [
      "# ",
      "## ",
      "### ",
      "#### ",
      "##### ",
      "###### ",
      "1. ",
      "- ",
      "  - ",
      "```gleam",
      "> ",
      "![",
      "_get_",
      "*bidirectional*",
      "`compose`",
      "](https",
      "\\_",
      "\\\n",
    ],
    fn(construct) {
      assert string.contains(all, construct)
    },
  )
  list.each(deck.cells(deck), fn(cell) {
    assert dialect.problems(cell.source) == []
  })
}

pub fn hand_written_fixture_test() {
  let assert Ok(text) = simplifile.read("test/fixtures/hand.md")
  let deck = parse(text)
  assert deck.violations(deck) == []
  assert sources(deck)
    == [
      ["A preamble paragraph.", "- a list\n- in the preamble"],
      [
        "# Imported",
        "Two blocks after a bare break.",
        "```\ncode with a blank line\n\ninside\n```",
        "An ID-less content cell.",
        "An ID-less notes cell.",
        "First with this ID.",
      ],
      ["Duplicate: gets a fresh ID."],
      [],
    ]
  let kinds = list.map(deck.cells(deck), fn(c) { c.kind })
  assert kinds
    == [
      Content,
      Content,
      Content,
      Content,
      Content,
      Content,
      Notes,
      Content,
      Content,
    ]
  // Rule 7: the first occurrence keeps the ID.
  let assert [_, second, third, fourth] = deck.slides
  assert id.to_string(third.id) == "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e01"
  assert id.to_string(fourth.id) != "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e01"
  let assert Ok(first_marked) = list.last(second.cells)
  assert id.to_string(first_marked.id) == "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e02"
  let assert [duplicate] = third.cells
  assert id.to_string(duplicate.id) != "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e02"
  // After printing, the file is canonical and parses back to the same deck.
  let printed = file.print(deck)
  assert parse(printed) == deck
  assert file.print(parse(printed)) == printed
}

pub fn empty_file_is_one_empty_slide_test() {
  let assert [Slide(_, [])] = parse("").slides
  let assert [Slide(_, [])] = parse("<!-- deck v1 -->\n\n").slides
  let assert [Slide(_, [])] = parse("\n  \n").slides
}

pub fn preamble_with_markers_test() {
  let deck = parse("<!-- cell -->\nHello\n---\n")
  assert sources(deck) == [["Hello"], []]
}

pub fn errors_test() {
  let supply = id.test_supply(1)
  assert file.parse("<!-- deck v2 -->\n", supply)
    == Error(ParseError(1, UnknownVersion(2)))
  assert file.parse("---\n<!-- deck v1 -->\n", supply)
    == Error(ParseError(2, MisplacedHeader))
  assert file.parse(
      "---\n\n<!-- slide 019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e01 -->\n",
      supply,
    )
    == Error(ParseError(3, SlideMarkerWithoutBreak))
}

pub fn structural_lines_inside_fences_test() {
  // P06: a marker inside an unclosed fence still starts a new cell.
  let deck =
    parse("---\n<!-- cell -->\n```\nopen fence\n<!-- cell -->\nafter\n")
  assert sources(deck) == [["```\nopen fence", "after"]]
}

pub fn near_markers_are_body_text_test() {
  let text =
    "---\n<!-- cell -->\n--- \n <!-- cell -->\n<!-- cell 019A2C41-7F10-7B2E-9C4D-1A2B3C4D5E02 -->\n<!-- deck v01 -->"
  let assert [[source]] = sources(parse(text))
  assert list.length(line.lines(source)) == 4
}

pub fn print_test() {
  let #(cell_id, _) = id.fresh(id.test_supply(2), id.empty_set())
  let #(slide_id, _) = id.fresh(id.test_supply(3), id.empty_set())
  let deck =
    Deck([
      Slide(slide_id, [
        Cell(cell_id, Notes, "a\n\nb"),
        Cell(cell_id, Content, ""),
      ]),
    ])
  assert file.print(deck)
    == "<!-- deck v1 -->\n\n---\n<!-- slide "
    <> id.to_string(slide_id)
    <> " -->\n\n<!-- notes "
    <> id.to_string(cell_id)
    <> " -->\na\n\nb\n\n<!-- cell "
    <> id.to_string(cell_id)
    <> " -->\n"
}

pub fn layout_example_round_trips_test() {
  let assert Ok(text) = simplifile.read("../examples/talk/layout.json")
  let assert Ok(layout) = file.parse_layout(text)
  assert file.print_layout(layout) == text
}

pub fn layout_rejects_bad_files_test() {
  let assert Error(_) = file.parse_layout("{\"version\": 3, \"cells\": {}}")
  let assert Error(_) =
    file.parse_layout(
      "{\"version\": 1, \"cells\": {\"019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e02\": {\"place\": {\"col\": 32, \"row\": 0, \"w\": 3, \"h\": 1}}}}",
    )
  let assert Error(_) =
    file.parse_layout(
      "{\"version\": 2, \"cells\": {\"019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e02\": {\"place\": {\"col\": 2, \"row\": 0, \"w\": 3, \"h\": 1}}}}",
    )
  let assert Error(_) =
    file.parse_layout("{\"version\": 1, \"cells\": {\"nope\": {}}}")
  let assert Ok(_) = file.parse_layout("{\"version\": 1, \"cells\": {}}")
}

/// Version 1 counted grid units of 60 pixels; it reads as pixels, in live
/// records and orphans alike, and prints as version 2.
pub fn layout_version_1_reads_as_pixels_test() {
  let assert Ok(layout) =
    file.parse_layout(
      "{\"version\": 1, \"cells\": {\"019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e02\": {\"place\": {\"col\": 2, \"row\": 1, \"w\": 28, \"h\": 3}}}, \"orphans\": [{\"kind\": \"cell\", \"id\": \"019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e07\", \"record\": {\"place\": {\"col\": 0, \"row\": 17, \"w\": 1, \"h\": 1}}, \"retired_at\": \"2026-10-27T14:03:00Z\"}]}",
    )
  let assert [record] = dict.values(layout.cells)
  assert record.place == Some(layout.Area(120, 60, 1680, 180))
  let assert [layout.CellOrphan(record: orphan, ..)] = layout.orphans
  assert orphan.place == Some(layout.Area(0, 1020, 60, 60))
  assert string.starts_with(file.print_layout(layout), "{\n  \"version\": 2,")
}
