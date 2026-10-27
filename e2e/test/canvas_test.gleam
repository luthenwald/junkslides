//// The slide pane in headless Chrome (D18): drawing, canvas mode, drag and
//// resize, overflow flags and theme reloads, each test on its own copy of
//// examples/talk. Run with `just e2e`.

import cdp.{type Page}
import filepath
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import harness.{
  cell, eventually, key, open, press, problem, record, selected, status,
}
import simplifile
import zeno/layout.{Area}

pub fn draws_the_slide_of_the_selection_test() {
  let #(page, _) = open("draw", 4921)
  // Slide 1: the heading is placed, the paragraph flows, notes are not drawn.
  assert drawn(page) == 2
  assert cdp.count(page, ".ze-fit .zeno-cell[data-placed]") == 1
  assert cdp.attribute(page, drawn_cell("03"), "data-variant") == Ok("quiet")
  assert cdp.attribute(page, drawn_cell("02"), "data-align") == Ok("start")
  assert cdp.count(page, ".ze-fit h1") == 1
  press(page, "}")
  press(page, "}")
  // Slide 3: three cells in the flow, lists drawn as lists.
  assert eventually(fn() { drawn(page) == 3 })
  assert cdp.count(page, ".ze-fit .zeno-body > .zeno-cell") == 3
  assert cdp.count(page, ".ze-fit ol > li") == 3
  // One probe per drawn cell of the deck, notes cells excepted.
  assert cdp.count(page, ".ze-probe") == 12
}

pub fn tab_and_canvas_keys_change_the_layout_test() {
  let #(page, folder) = open("canvas-keys", 4922)
  press(page, "}")
  press(page, "}")
  press(page, "Tab")
  assert eventually(fn() { string.contains(status(page), "canvas") })
  press(page, "j")
  assert selected(page) == cell("09")
  // Placed where it is drawn: the body spans 28 columns from column 2.
  press(page, "Enter")
  assert eventually(fn() { place(folder, "09") != None })
  let assert Some(Area(col: 2, row: row, w: 28, h: h)) = place(folder, "09")
  key(page, "l", [cdp.Alt])
  assert eventually(fn() { place(folder, "09") == Some(Area(3, row, 28, h)) })
  press(page, "ArrowDown")
  assert eventually(fn() {
    place(folder, "09") == Some(Area(3, row + 1, 28, h))
  })
  press(page, "H")
  key(page, "ArrowDown", [cdp.Shift])
  assert eventually(fn() {
    place(folder, "09") == Some(Area(3, row + 1, 27, h + 1))
  })
  press(page, "f")
  assert eventually(fn() { place(folder, "09") == None })
  press(page, "v")
  assert eventually(fn() { record(folder, "09").variant == Some("large") })
  press(page, "a")
  assert eventually(fn() { record(folder, "09").align == Some(layout.Start) })
  press(page, "u")
  assert eventually(fn() { record(folder, "09").align == None })
  press(page, "Tab")
  assert eventually(fn() { string.contains(status(page), "command") })
  // Command keys work again.
  press(page, "j")
  assert selected(page) == cell("0a")
}

pub fn click_selects_and_drag_moves_test() {
  let #(page, folder) = open("drag", 4923)
  // The heading of slide 1 is placed at col 2, row 1, 28 by 3. Moved by
  // (5, 2), it stops at col 4, where its 28 columns end at the edge.
  let start = grid_point(page, #(4, 2))
  let end = grid_point(page, #(9, 4))
  let assert Ok(_) = cdp.mouse(page, cdp.Press, start.0, start.1)
  glide(page, start, end)
  // A preview while the button is held, and nothing sent yet.
  assert eventually(fn() {
    cdp.attribute(page, drawn_cell("02"), "style")
    |> result.unwrap("")
    |> string.contains("grid-area:4 / 5 / span 3 / span 28")
  })
  assert place(folder, "02") == Some(Area(2, 1, 28, 3))
  let assert Ok(_) = cdp.mouse(page, cdp.Release, end.0, end.1)
  assert eventually(fn() { place(folder, "02") == Some(Area(4, 3, 28, 3)) })
  assert string.contains(status(page), "canvas")
  assert selected(page) == cell("02")
  // Its handle resizes it, the hovered cell becoming the corner.
  let assert Ok(handle) = cdp.box(page, ".ze-handle")
  let #(x, y) = #(handle.x +. handle.w /. 2.0, handle.y +. handle.h /. 2.0)
  let assert Ok(_) = cdp.mouse(page, cdp.Press, x, y)
  glide(page, #(x, y), grid_point(page, #(20, 8)))
  let #(x, y) = grid_point(page, #(20, 8))
  let assert Ok(_) = cdp.mouse(page, cdp.Release, x, y)
  assert eventually(fn() { place(folder, "02") == Some(Area(4, 3, 17, 6)) })
  // A click without a move changes nothing.
  drag(page, #(8, 4), #(8, 4))
  assert place(folder, "02") == Some(Area(4, 3, 17, 6))
  // One undo step per drag.
  press(page, "u")
  assert eventually(fn() { place(folder, "02") == Some(Area(4, 3, 28, 3)) })
}

pub fn dragging_a_flowing_cell_places_it_test() {
  let #(page, folder) = open("drag-out", 4924)
  press(page, "}")
  press(page, "}")
  assert eventually(fn() { drawn(page) == 3 })
  // A row well inside the list, away from its edges.
  let assert Ok(list) = cdp.box(page, drawn_cell("09"))
  let assert Ok(slide) = cdp.box(page, ".ze-fit .zeno-slide")
  let row = float.truncate({ list.y -. slide.y } /. { slide.w /. 32.0 }) + 1
  drag(page, #(3, row), #(2, row + 2))
  assert eventually(fn() { place(folder, "09") != None })
  let assert Some(Area(col:, w:, h:, ..)) = place(folder, "09")
  // Its rendered size, rounded up to whole units, moved by the drag: the
  // body starts at col 2 and spans 28 columns.
  assert col == 1
  assert w == 28
  assert h >= 2 && h <= 5
  assert drawn(page) == 3
  assert cdp.count(page, ".ze-fit .zeno-cell[data-placed]") == 1
}

pub fn overflow_is_flagged_test() {
  let #(page, _) = open("overflow", 4925)
  // The heading is placed three units high; four more paragraphs overflow.
  press(page, "Enter")
  let assert Ok(_) = cdp.type_text(page, "\n\nOne\n\nTwo\n\nThree\n\nFour")
  press(page, "Escape")
  assert eventually(fn() { cdp.count(page, ".ze-fit .ze-overflow") == 1 })
  assert eventually(fn() { string.contains(status(page), "1 cell overflows") })
  assert string.contains(problem(page), "Does not fit its box on the slide.")
  press(page, "u")
  assert eventually(fn() { cdp.count(page, ".ze-fit .ze-overflow") == 0 })
  assert !string.contains(status(page), "overflow")
}

pub fn theme_reloads_test() {
  let #(page, folder) = open("theme", 4926)
  let assert Ok(_) =
    simplifile.write(
      filepath.join(folder, "theme.css"),
      ":root { --zeno-variants: \"loud\"; }\n"
        <> ".zeno-body { grid-area: 3 / 3 / 17 / 31; }\n"
        <> ".zeno-cell[data-variant=\"large\"] { font-size: 400px; }\n",
    )
  assert eventually(fn() {
    cdp.count(page, "link[href=\"/theme.css?v=1\"]") == 1
  })
  // The previous theme's link goes once the new one has loaded.
  assert eventually(fn() { cdp.count(page, "link[href^=\"/theme.css\"]") == 1 })
  // The new theme makes the large heading overflow its placed box.
  assert eventually(fn() { cdp.count(page, ".ze-fit .ze-overflow") == 1 })
  // Variants come from the new list: `large` is gone, so none, then `loud`.
  press(page, "Tab")
  press(page, "v")
  assert eventually(fn() { record(folder, "02").variant == None })
  press(page, "v")
  assert eventually(fn() { record(folder, "02").variant == Some("loud") })
}

// Helpers ----------------------------------------------------------------------

fn drawn(page: Page) -> Int {
  cdp.count(page, ".ze-fit .zeno-cell")
}

fn drawn_cell(suffix: String) -> String {
  ".ze-fit .zeno-cell[data-cell=\"" <> cell(suffix) <> "\"]"
}

fn place(folder: String, suffix: String) -> option.Option(layout.Area) {
  record(folder, suffix).place
}

/// The centre of a grid cell of the visible slide, in viewport pixels.
fn grid_point(page: Page, at: #(Int, Int)) -> #(Float, Float) {
  let assert Ok(slide) = cdp.box(page, ".ze-fit .zeno-slide")
  let unit = slide.w /. 32.0
  #(
    slide.x +. { int.to_float(at.0) +. 0.5 } *. unit,
    slide.y +. { int.to_float(at.1) +. 0.5 } *. unit,
  )
}

/// Press on one grid cell, move to another in small steps, release.
fn drag(page: Page, from: #(Int, Int), to: #(Int, Int)) -> Nil {
  let start = grid_point(page, from)
  let end = grid_point(page, to)
  let assert Ok(_) = cdp.mouse(page, cdp.Press, start.0, start.1)
  glide(page, start, end)
  let assert Ok(_) = cdp.mouse(page, cdp.Release, end.0, end.1)
  Nil
}

fn glide(page: Page, from: #(Float, Float), to: #(Float, Float)) -> Nil {
  list.each([1, 2, 3, 4, 5, 6, 7, 8], fn(step) {
    let t = int.to_float(step) /. 8.0
    let assert Ok(_) =
      cdp.mouse(
        page,
        cdp.Move,
        from.0 +. { to.0 -. from.0 } *. t,
        from.1 +. { to.1 -. from.1 } *. t,
      )
  })
}
