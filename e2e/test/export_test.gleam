//// An exported page in headless Chrome (D18), opened from its files: slides,
//// fitting the window, stepping with keys, links to a slide, and printing.

import cdp.{type Page}
import filepath
import gleam/bit_array
import gleam/dynamic/decode
import gleam/float
import gleam/json
import gleam/list
import gleam/string
import harness.{deck, eventually, open, press, status}
import simplifile

/// Exports a fresh copy of the example deck with the `E` key and opens the page.
fn exported(name: String, port: Int) -> #(Page, String) {
  let #(page, folder) = open(name, port)
  let before = deck(folder)
  press(page, "E")
  assert eventually(fn() { string.contains(status(page), "Exported to ") })
  // Nothing changes in the deck itself.
  assert deck(folder) == before
  let url = "file://" <> filepath.join(folder, "export/index.html")
  let assert Ok(_) = cdp.viewport(page, 1280, 800)
  let assert Ok(_) = cdp.open(page, url, ".zeno-frame")
  #(page, url)
}

fn close(a: Float, b: Float) -> Bool {
  float.absolute_value(a -. b) <. 1.0
}

pub fn the_page_holds_every_slide_and_no_script_test() {
  let #(page, _) = exported("export-page", 4941)
  assert cdp.count(page, ".zeno-frame") == 7
  assert cdp.count(page, ".zeno-frame .zeno-slide") == 7
  assert cdp.count(page, ".zeno-page") == 7
  assert cdp.count(page, "table") == 1
  assert cdp.count(page, "script") == 0
  // Placed cells kept their box, and the theme is there.
  assert cdp.count(page, ".zeno-cell[data-placed]") > 0
  assert cdp.computed(page, ".zeno-slide", "background-color")
    == Ok("rgb(250, 250, 250)")
}

pub fn the_page_loads_the_default_fonts_from_its_own_folder_test() {
  let #(page, _) = exported("export-fonts", 4948)
  let has = fn(font) {
    case cdp.loaded_fonts(page) {
      Ok(fonts) -> string.contains(fonts, font)
      Error(_) -> False
    }
  }
  assert eventually(fn() { has("et-book normal") })
  assert eventually(fn() { has("Victor Mono normal") })
}

pub fn a_slide_fits_the_window_at_any_size_test() {
  let #(page, url) = exported("export-fit", 4942)
  // Wider than 16:9 or narrower, the slide is whole and centred.
  let assert Ok(box) = cdp.box(page, "[id='1'] .zeno-slide")
  assert close(box.w, 1280.0)
  assert close(box.h, 720.0)
  assert close(box.y, 40.0)
  assert close(box.x, 0.0)
  let assert Ok(_) = cdp.viewport(page, 1000, 400)
  let assert Ok(_) = cdp.open(page, url, ".zeno-frame")
  assert eventually(fn() {
    case cdp.box(page, "[id='1'] .zeno-slide") {
      Ok(box) -> close(box.h, 400.0) && close(box.x, 144.5)
      Error(_) -> False
    }
  })
}

pub fn keys_step_from_slide_to_slide_test() {
  let #(page, _) = exported("export-keys", 4943)
  let at_top = fn(number) {
    case cdp.box(page, "[id='" <> number <> "']") {
      Ok(box) -> close(box.y, 0.0)
      Error(_) -> False
    }
  }
  assert at_top("1")
  press(page, "ArrowDown")
  assert eventually(fn() { at_top("2") })
  press(page, "ArrowDown")
  assert eventually(fn() { at_top("3") })
  press(page, "ArrowUp")
  assert eventually(fn() { at_top("2") })
}

pub fn a_link_opens_its_slide_test() {
  let #(page, url) = exported("export-link", 4944)
  let assert Ok(_) = cdp.open(page, url <> "#3", ".zeno-frame")
  assert eventually(fn() {
    case cdp.box(page, "[id='3']") {
      Ok(box) -> close(box.y, 0.0)
      Error(_) -> False
    }
  })
}

pub fn printing_gives_one_page_per_slide_test() {
  let #(page, _) = exported("export-print", 4945)
  let assert Ok(reply) =
    cdp.call(page, "Page.printToPDF", [
      #("preferCSSPageSize", json.bool(True)),
      #("printBackground", json.bool(True)),
    ])
  let assert Ok(data) = decode.run(reply, decode.at(["data"], decode.string))
  let assert Ok(pdf) = bit_array.base64_decode(data)
  assert pdf_pages(pdf) == 7
}

/// The whole way with a real browser: the key, a folder name that needs
/// escaping, one page per slide, and the slide's fonts inside the file.
pub fn the_key_prints_a_pdf_with_every_slide_and_its_fonts_test() {
  let #(page, folder) = open("export pdf #2", 4949)
  let before = deck(folder)
  press(page, "F")
  let target = filepath.join(folder, "export/export pdf #2.pdf")
  let assert Ok(Nil) =
    cdp.wait(30_000, fn() { string.contains(status(page), "Exported to ") })
  let assert Ok(pdf) = simplifile.read_bits(target)
  assert pdf_pages(pdf) == 7
  let text = latin1(pdf, []) |> string.concat
  assert string.contains(text, "ETBook")
  assert string.contains(text, "VictorMono")
  assert deck(folder) == before
}

/// Page objects in the file. Latin-1 bytes are all this needs to look at.
fn pdf_pages(pdf: BitArray) -> Int {
  latin1(pdf, [])
  |> string.concat
  |> string.split("/Type /Page")
  |> list.drop(1)
  |> list.filter(fn(rest) { !string.starts_with(rest, "s") })
  |> list.length
}

fn latin1(bytes: BitArray, done: List(String)) -> List(String) {
  case bytes {
    <<byte, rest:bytes>> if byte < 128 ->
      case bit_array.to_string(<<byte>>) {
        Ok(text) -> latin1(rest, [text, ..done])
        Error(Nil) -> latin1(rest, done)
      }
    <<_, rest:bytes>> -> latin1(rest, ["?", ..done])
    _ -> list.reverse(done)
  }
}
