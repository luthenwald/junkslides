//// S2 in headless Chrome: growing text areas and overflow reported to the
//// Lustre model through CSS animation events.

import cdp.{type Page}
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import static

const port = 4883

/// Measured one frame later, after Lustre has rendered the last input.
fn height(page: Page, selector: String) -> Float {
  process.sleep(50)
  cdp.box(page, selector) |> result.map(fn(b) { b.h }) |> result.unwrap(-1.0)
}

fn state(page: Page) -> String {
  cdp.html(page, "#state") |> result.unwrap("")
}

pub fn s2_test() {
  let _ = static.serve("../s2_measure/dist", port)
  let assert Ok(page) = cdp.connect(9333)
  let assert Ok(_) = cdp.viewport(page, 1280, 800)
  let assert Ok(_) =
    cdp.open(page, "http://127.0.0.1:" <> int.to_string(port) <> "/", "#state")

  // Text areas: five lines, then one long wrapping line.
  let grown =
    list.map(["#ta-field", "#ta-mirror", "#ta-rows"], fn(id) {
      let before = height(page, id)
      let assert Ok(_) = cdp.focus(page, id)
      let assert Ok(_) = cdp.type_text(page, "one\ntwo\nthree\nfour\nfive")
      let lines = height(page, id)
      let assert Ok(_) = cdp.type_text(page, " " <> string.repeat("wrap ", 60))
      let wrapped = height(page, id)
      io.println(
        "\n"
        <> id
        <> " heights: empty "
        <> float.to_string(before)
        <> ", five lines "
        <> float.to_string(lines)
        <> ", with a wrapping line "
        <> float.to_string(wrapped),
      )
      #(id, lines >. before, wrapped >. lines)
    })
  assert grown
    == [
      #("#ta-field", True, True),
      #("#ta-mirror", True, True),
      #("#ta-rows", True, False),
    ]

  // Overflow: the box is 120 px high and lines are 30 px. Two lines fit.
  let assert Ok(_) =
    cdp.wait(2000, fn() { string.contains(state(page), "rows 2") })
  io.println("start: " <> state(page))
  assert string.contains(state(page), "auto fits")
  list.each([1, 2, 3], fn(_) {
    let assert Ok(_) = cdp.click(page, "#more")
  })
  let assert Ok(_) =
    cdp.wait(2000, fn() { string.contains(state(page), "auto overflows") })
  io.println("five lines: " <> state(page))
  assert string.contains(state(page), "rows 5")
  list.each([1, 2, 3], fn(_) {
    let assert Ok(_) = cdp.click(page, "#less")
  })
  let assert Ok(_) =
    cdp.wait(2000, fn() { string.contains(state(page), "rows 2") })
  io.println("back to two: " <> state(page))
  assert string.contains(state(page), "auto fits")
}
