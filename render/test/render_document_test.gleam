import gleam/dict
import gleam/string
import zeno/deck.{Cell, Content, Deck, Notes, Slide}
import zeno/id
import zeno/layout
import zeno/render

const slide_a = "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e01"

const slide_b = "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e02"

const flowing = "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e03"

const placed = "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e04"

const notes = "019a2c41-7f10-7b2e-9c4d-1a2b3c4d5e05"

fn id_of(text: String) -> id.Id(tag) {
  let assert Ok(parsed) = id.parse(text)
  parsed
}

fn page(has_theme: Bool) -> String {
  page_with(False, has_theme)
}

fn page_with(has_settings: Bool, has_theme: Bool) -> String {
  let deck =
    Deck([
      Slide(id_of(slide_a), [
        Cell(id_of(flowing), Content, "a <b> & c"),
        Cell(id_of(placed), Content, "there"),
        Cell(id_of(notes), Notes, "only for me"),
      ]),
      Slide(id_of(slide_b), []),
    ])
  let assert Ok(laid) =
    layout.apply(
      layout.empty(),
      deck,
      layout.Place(id_of(placed), layout.Area(120, 60, 600, 300)),
    )
  render.document(
    deck,
    laid,
    dict.new(),
    dict.new(),
    "My <talk>",
    has_settings,
    has_theme,
  )
}

pub fn every_slide_has_a_numbered_frame_test() {
  let html = page(True)
  assert string.starts_with(string.lowercase(html), "<!doctype html>")
  assert string.contains(html, "<section class=\"zeno-frame\" id=\"1\">")
  assert string.contains(html, "<section class=\"zeno-frame\" id=\"2\">")
  assert string.contains(html, ">01</span>")
  // A slide with nothing drawn stays, so numbers match the editor's.
  assert string.contains(
    html,
    ">02</span><span class=\"zeno-page-total\"><span class=\"zeno-page-slash\">/</span>02</span>",
  )
}

pub fn notes_are_left_out_test() {
  assert !string.contains(page(True), "only for me")
}

pub fn placed_cells_keep_their_box_and_leave_the_flow_test() {
  let html = page(True)
  assert string.contains(html, "left:120px")
  assert string.contains(html, "top:60px")
  assert string.contains(html, "width:600px")
  assert string.contains(html, "height:300px")
  let assert Ok(#(_, after_body)) =
    string.split_once(html, "<div class=\"zeno-body\">")
  let assert Ok(#(in_body, _)) = string.split_once(after_body, "data-placed")
  assert string.contains(in_body, "a &lt;b&gt; &amp; c")
  assert !string.contains(in_body, "there")
}

pub fn text_is_escaped_test() {
  let html = page(True)
  assert string.contains(html, "My &lt;talk&gt;")
  assert !string.contains(html, "<b>")
}

pub fn no_script_at_all_test() {
  assert !string.contains(string.lowercase(page(True)), "<script")
}

pub fn the_theme_comes_after_the_page_styles_test() {
  let html = page(True)
  let assert [_, after_styles] = string.split(html, "</style><link")
  assert string.contains(after_styles, "href=\"theme.css\"")
  assert !string.contains(page(False), "href=\"theme.css\"")
}

pub fn settings_come_between_page_styles_and_theme_test() {
  let html = page_with(True, True)
  let assert [_, after_styles] = string.split(html, "</style><link")
  let assert Ok(#(before_theme, _)) =
    string.split_once(after_styles, "href=\"theme.css\"")
  assert string.contains(before_theme, "href=\"settings.css\"")
  assert !string.contains(page_with(False, True), "settings.css")
}

pub fn numbers_are_padded_test() {
  assert render.number(0, 12) == "01/12"
  assert render.number(6, 120) == "007/120"
}
