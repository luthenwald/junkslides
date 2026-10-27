//// S1 in headless Chrome: fitting, dragging, clamping, resizing.

import cdp.{type Page, Move, Press, Release}
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import static

const port = 4881

fn setup() -> Page {
  let _ = static.serve("../s1_drag/dist", port)
  let assert Ok(page) = cdp.connect(9333)
  let assert Ok(_) = cdp.viewport(page, 1280, 800)
  let assert Ok(_) =
    cdp.open(page, "http://127.0.0.1:" <> int.to_string(port) <> "/", "#box")
  page
}

/// The centre of grid cell (col, row) in viewport pixels.
fn cell(page: Page, col: Int, row: Int) -> #(Float, Float) {
  let assert Ok(slide) = cdp.box(page, "#slide")
  let unit = slide.w /. 32.0
  #(
    slide.x +. { int.to_float(col) +. 0.5 } *. unit,
    slide.y +. { int.to_float(row) +. 0.5 } *. unit,
  )
}

/// Press at one cell, move through the cells in between, release at the last.
fn drag(page: Page, from: #(Float, Float), path: List(#(Float, Float))) -> Nil {
  let assert Ok(_) = cdp.mouse(page, Press, from.0, from.1)
  // Lustre renders the hit overlay on the next animation frame.
  process.sleep(30)
  list.each(path, fn(p) {
    let assert Ok(_) = cdp.mouse(page, Move, p.0, p.1)
  })
  let assert Ok(last) = list.last(path)
  let assert Ok(_) = cdp.mouse(page, Release, last.0, last.1)
  Nil
}

fn steps(
  page: Page,
  from: #(Int, Int),
  to: #(Int, Int),
) -> List(#(Float, Float)) {
  let n =
    int.max(
      int.absolute_value(to.0 - from.0),
      int.absolute_value(to.1 - from.1),
    )
  list.map(range(1, n), fn(i) {
    cell(
      page,
      from.0 + { to.0 - from.0 } * i / n,
      from.1 + { to.1 - from.1 } * i / n,
    )
  })
}

fn area(page: Page) -> String {
  cdp.attribute(page, "#box", "data-area") |> result.unwrap("?")
}

pub fn s1_test() {
  let page = setup()

  // Fitting: 1280x800 viewport, so the slide is scaled to 1280x720.
  let assert Ok(slide) = cdp.box(page, "#slide")
  io.println(
    "\nslide box "
    <> float.to_string(slide.w)
    <> "x"
    <> float.to_string(slide.h),
  )
  assert cdp.round(slide.w) == 1280
  assert cdp.round(slide.h) == 720
  assert cdp.round(slide.x) == 0
  assert cdp.round(slide.y) == 40
  assert area(page) == "4 3 8 4"

  // Move: grab at (5, 4), drag by (+10, +6).
  let start = now()
  drag(page, cell(page, 5, 4), steps(page, #(5, 4), #(15, 10)))
  io.println("move drag of 10 steps: " <> int.to_string(now() - start) <> " ms")
  assert area(page) == "14 9 8 4"

  // Resize from the handle: grow to (25, 14), shrink past the corner (the
  // minimum of one unit applies), then grow back to (20, 12).
  let assert Ok(handle) = cdp.box(page, "#handle")
  let h = #(handle.x +. handle.w /. 2.0, handle.y +. handle.h /. 2.0)
  drag(page, h, [cell(page, 25, 14)])
  assert area(page) == "14 9 12 6"
  let assert Ok(handle) = cdp.box(page, "#handle")
  let h = #(handle.x +. handle.w /. 2.0, handle.y +. handle.h /. 2.0)
  drag(page, h, [cell(page, 10, 5), cell(page, 20, 12)])
  assert area(page) == "14 9 7 4"

  // Clamp: drag far past the right and bottom edges.
  drag(page, cell(page, 15, 10), steps(page, #(15, 10), #(31, 17)))
  assert area(page) == "25 14 7 4"

  // Release outside the slide (below it, still in the window).
  let below = #(640.0, 790.0)
  let assert Ok(_) =
    cdp.mouse(page, Press, cell(page, 26, 15).0, cell(page, 26, 15).1)
  process.sleep(30)
  let assert Ok(_) =
    cdp.mouse(page, Move, cell(page, 20, 15).0, cell(page, 20, 15).1)
  let assert Ok(_) = cdp.mouse(page, Move, below.0, below.1)
  let assert Ok(_) = cdp.mouse(page, Release, below.0, below.1)
  assert area(page) == "19 14 7 4"
  let assert Ok(status) = cdp.html(page, "#status")
  io.println("status: " <> status)

  // Smoothness proxy: 200 moves back and forth during one drag.
  let assert Ok(_) =
    cdp.mouse(page, Press, cell(page, 20, 16).0, cell(page, 20, 16).1)
  let start = now()
  list.each(range(1, 200), fn(i) {
    let p = cell(page, 10 + i % 10, 8)
    let assert Ok(_) = cdp.mouse(page, Move, p.0, p.1)
  })
  let per_move = { now() - start } / 200
  let assert Ok(_) =
    cdp.mouse(page, Release, cell(page, 19, 8).0, cell(page, 19, 8).1)
  io.println(
    "per move including CDP round trip: " <> int.to_string(per_move) <> " ms",
  )
  process.sleep(10)
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic(unit: Unit) -> Int

type Unit {
  Millisecond
}

fn now() -> Int {
  monotonic(Millisecond)
}

fn range(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..range(from + 1, to)]
  }
}
