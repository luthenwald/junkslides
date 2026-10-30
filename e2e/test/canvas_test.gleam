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
  cell, eventually, key, open, press, problem, record, saved_view, selected,
  status,
}
import simplifile
import zeno/layout.{Area}

pub fn draws_the_slide_of_the_selection_test() {
  let #(page, _) = open("draw", 4921)
  // Slide 1: the heading and the paragraph are placed, notes are not drawn.
  assert drawn(page) == 2
  assert cdp.count(page, ".ze-fit .zeno-cell[data-placed]") == 2
  assert cdp.attribute(page, drawn_cell("03"), "data-variant") == Ok("quiet")
  assert cdp.attribute(page, drawn_cell("02"), "data-align") == Ok("start")
  assert cdp.count(page, ".ze-fit h1") == 1
  // The slide's number, in the slide's lower right corner.
  assert page_number(page) == "01/06"
  let assert Ok(slide) = cdp.box(page, ".ze-fit .zeno-slide")
  let assert Ok(number) = cdp.box(page, ".ze-fit .zeno-page")
  assert number.x >. slide.x +. slide.w *. 0.8
  assert number.y >. slide.y +. slide.h *. 0.8
  press(page, "}")
  press(page, "}")
  // Slide 3: three cells in the flow, lists drawn as lists.
  assert eventually(fn() { drawn(page) == 3 })
  assert page_number(page) == "03/06"
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
  // Placed where it is drawn: the theme's body spans 1680 pixels from 120.
  press(page, "Enter")
  assert eventually(fn() { place(folder, "09") != None })
  let assert Some(Area(x: 120, y: y, w: 1680, h: h)) = place(folder, "09")
  // Nudges and resizes move edges onto the next line of the snap step,
  // 30 pixels unless the view says otherwise.
  key(page, "l", [cdp.Alt])
  assert eventually(fn() { place(folder, "09") == Some(Area(150, y, 1680, h)) })
  press(page, "ArrowDown")
  let y = next_line(y, 30)
  assert eventually(fn() { place(folder, "09") == Some(Area(150, y, 1680, h)) })
  press(page, "H")
  key(page, "ArrowDown", [cdp.Shift])
  let h = next_line(y + h, 30) - y
  assert eventually(fn() { place(folder, "09") == Some(Area(150, y, 1650, h)) })
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
  // The heading of slide 1 is placed at (120, 180), 1680 by 180. Moved by
  // five grid cells left and two down, it hangs off the left edge.
  let start = grid_point(page, #(9, 4))
  let end = grid_point(page, #(4, 6))
  let assert Ok(_) = cdp.mouse(page, cdp.Press, start.0, start.1)
  glide(page, start, end)
  // A preview while the button is held, and nothing sent yet.
  assert eventually(fn() {
    let style = cdp.attribute(page, drawn_cell("02"), "style")
    let style = result.unwrap(style, "")
    string.contains(style, "left:-180px") && string.contains(style, "top:300px")
  })
  assert place(folder, "02") == Some(Area(120, 180, 1680, 180))
  let assert Ok(_) = cdp.mouse(page, cdp.Release, end.0, end.1)
  assert eventually(fn() {
    place(folder, "02") == Some(Area(-180, 300, 1680, 180))
  })
  assert string.contains(status(page), "canvas")
  assert selected(page) == cell("02")
  // Its handle resizes it, the pointer snapped to 30 pixels becoming the
  // corner.
  let assert Ok(handle) = cdp.box(page, ".ze-handle")
  let #(x, y) = #(handle.x +. handle.w /. 2.0, handle.y +. handle.h /. 2.0)
  let assert Ok(_) = cdp.mouse(page, cdp.Press, x, y)
  glide(page, #(x, y), grid_point(page, #(20, 10)))
  let #(x, y) = grid_point(page, #(20, 10))
  let assert Ok(_) = cdp.mouse(page, cdp.Release, x, y)
  assert eventually(fn() {
    place(folder, "02") == Some(Area(-180, 300, 1410, 330))
  })
  // A click without a move changes nothing.
  drag(page, #(8, 6), #(8, 6))
  assert place(folder, "02") == Some(Area(-180, 300, 1410, 330))
  // One undo step per drag.
  press(page, "u")
  assert eventually(fn() {
    place(folder, "02") == Some(Area(-180, 300, 1680, 180))
  })
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
  let assert Some(Area(x:, w:, h:, ..)) = place(folder, "09")
  // Its rendered size, moved by the drag: the body starts at 120 pixels
  // and spans 1680, and the move snaps to the step.
  assert x == 60
  assert w == 1680
  assert h > 60 && h <= 300
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

pub fn source_lines_are_kept_test() {
  let #(page, _) = open("lines", 4929)
  // The heading gets a second line, indented under its first word.
  press(page, "Enter")
  let assert Ok(_) = cdp.type_text(page, "\n    and why not")
  press(page, "Escape")
  assert eventually(fn() { cdp.count(page, ".ze-fit h1 br") == 1 })
  assert cdp.count(page, ".ze-fit h1 .zeno-indent") == 1
  let assert Ok(heading) = cdp.html(page, ".ze-fit h1")
  assert string.contains(
    heading,
    "<span class=\"zeno-indent\">  </span>and why not",
  )
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

pub fn dragging_past_the_edges_test() {
  let #(page, folder) = open("drag-edges", 4927)
  let assert Ok(slide) = cdp.box(page, ".ze-fit .zeno-slide")
  // The heading moves sixteen grid cells right, with the pointer let go in
  // the pane's margin below the slide: it hangs off the right and bottom
  // edges, ten pixels of it left on the slide at the bottom.
  let start = grid_point(page, #(4, 4))
  let end = #(start.0 +. 16.0 *. slide.w /. 32.0, slide.y +. slide.h +. 40.0)
  let assert Ok(_) = cdp.mouse(page, cdp.Press, start.0, start.1)
  glide(page, start, end)
  let assert Ok(_) = cdp.mouse(page, cdp.Release, end.0, end.1)
  assert eventually(fn() {
    place(folder, "02") == Some(Area(1080, 1070, 1680, 180))
  })
  // Drawn over the margin, past the slide's edges.
  let assert Ok(box) = cdp.box(page, drawn_cell("02"))
  assert box.x +. box.w >. slide.x +. slide.w
  assert box.y +. box.h >. slide.y +. slide.h
  // Opened again, it is drawn where it was left.
  let assert Ok(_) = cdp.open(page, "http://127.0.0.1:4927/", ".ze-selected")
  assert eventually(fn() {
    let style = cdp.attribute(page, drawn_cell("02"), "style")
    let style = result.unwrap(style, "")
    string.contains(style, "left:1080px")
    && string.contains(style, "top:1070px")
  })
  // Its visible strip can be grabbed and brought back.
  let assert Ok(box) = cdp.box(page, drawn_cell("02"))
  let grab = #(box.x +. 20.0, box.y +. 2.0)
  let back = #(
    grab.0 -. 16.0 *. slide.w /. 32.0,
    grab.1 -. 14.0 *. slide.w /. 32.0,
  )
  let assert Ok(_) = cdp.mouse(page, cdp.Press, grab.0, grab.1)
  glide(page, grab, back)
  let assert Ok(_) = cdp.mouse(page, cdp.Release, back.0, back.1)
  assert eventually(fn() {
    case place(folder, "02") {
      Some(Area(x: 120, y:, w: 1680, h: 180)) -> y >= 180 && y <= 300
      _ -> False
    }
  })
}

pub fn snap_step_is_chosen_and_kept_test() {
  let #(page, folder) = open("snap", 4928)
  assert string.contains(status(page), "snap")
  assert cdp.attribute(page, ".ze-snap option[selected]", "value") == Ok("30")
  press(page, "Tab")
  // Finer, then back to coarser twice: 20, then 30, then 60.
  press(page, "g")
  assert eventually(fn() { saved_view(folder).snap == 20 })
  assert string.contains(status(page), "snap 20 px")
  press(page, "G")
  press(page, "G")
  assert eventually(fn() { saved_view(folder).snap == 60 })
  assert eventually(fn() {
    cdp.attribute(page, ".ze-snap option[selected]", "value") == Ok("60")
  })
  // Keys still reach the canvas, and nudges use the new step.
  press(page, "ArrowRight")
  assert eventually(fn() {
    place(folder, "02") == Some(Area(180, 180, 1680, 180))
  })
  // Off: every pixel. A drag of a little more than one grid cell keeps
  // the odd pixels.
  list.each([1, 2, 3, 4, 5, 6], fn(_) { press(page, "g") })
  assert eventually(fn() { saved_view(folder).snap == 0 })
  assert eventually(fn() { string.contains(status(page), "snap off") })
  let assert Ok(slide) = cdp.box(page, ".ze-fit .zeno-slide")
  let start = grid_point(page, #(6, 4))
  let end = #(start.0 +. slide.w /. 32.0 *. 1.3, start.1)
  let assert Ok(_) = cdp.mouse(page, cdp.Press, start.0, start.1)
  glide(page, start, end)
  let assert Ok(_) = cdp.mouse(page, cdp.Release, end.0, end.1)
  assert eventually(fn() {
    case place(folder, "02") {
      Some(Area(x:, y: 180, ..)) -> x > 240 && x % 30 != 0
      _ -> False
    }
  })
}

fn page_number(page: Page) -> String {
  let assert Ok(html) = cdp.html(page, ".ze-fit .zeno-page")
  html
  |> string.replace("<div class=\"zeno-page\">", "")
  |> string.replace("</div>", "")
}

fn drawn(page: Page) -> Int {
  cdp.count(page, ".ze-fit .zeno-cell")
}

fn drawn_cell(suffix: String) -> String {
  ".ze-fit .zeno-cell[data-cell=\"" <> cell(suffix) <> "\"]"
}

/// The next line of the snap step after `px`.
fn next_line(px: Int, step: Int) -> Int {
  px / step * step + step
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
