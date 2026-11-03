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

/// A font the theme loads from the deck's own `fonts/` folder, not `assets/`,
/// is in the export and loads from there. The PDF names fonts after their
/// files, so this is the check that tells the theme's copy from the default.
pub fn the_page_loads_a_font_the_theme_keeps_in_the_deck_test() {
  let folder = harness.prepare("export-theme-font")
  let font = filepath.join(folder, "fonts/deck-font.woff2")
  let assert Ok(Nil) =
    simplifile.create_directory_all(filepath.join(folder, "fonts"))
  let assert Ok(Nil) =
    simplifile.copy_file("../server/priv/fonts/victor-mono-regular.woff2", font)
  let assert Ok(Nil) =
    simplifile.append(
      filepath.join(folder, "theme.css"),
      "@font-face { font-family: \"Deck Font\"; src: url(\"fonts/deck-font.woff2\"); }
.zeno-slide { font-family: \"Deck Font\"; }
",
    )
  let #(page, _, _, _) = harness.open_folder(folder, 4950)
  press(page, "E")
  assert eventually(fn() { string.contains(status(page), "Exported to ") })
  let assert Ok(_) =
    cdp.open(
      page,
      "file://" <> filepath.join(folder, "export/index.html"),
      ".zeno-frame",
    )
  assert eventually(fn() {
    case cdp.loaded_fonts(page) {
      Ok(fonts) -> string.contains(fonts, "Deck Font normal")
      Error(_) -> False
    }
  })
}

/// A font named only in zeno.toml is in the export and loads from there.
pub fn the_page_loads_a_font_the_settings_name_test() {
  let folder = harness.prepare("export-settings-font")
  let assert Ok(Nil) =
    simplifile.create_directory_all(filepath.join(folder, "type"))
  let assert Ok(Nil) =
    simplifile.copy_file(
      "../server/priv/fonts/victor-mono-regular.woff2",
      filepath.join(folder, "type/settings-font.woff2"),
    )
  let assert Ok(Nil) =
    simplifile.write(filepath.join(folder, "theme.css"), ".x { }\n")
  let assert Ok(Nil) =
    simplifile.write(
      filepath.join(folder, "zeno.toml"),
      "[font.text]\nfamily = \"Settings Font\"\n"
        <> "regular = \"type/settings-font.woff2\"\n",
    )
  let #(page, _, _, _) = harness.open_folder(folder, 4953)
  press(page, "E")
  assert eventually(fn() { string.contains(status(page), "Exported to ") })
  let assert Ok(_) =
    cdp.open(
      page,
      "file://" <> filepath.join(folder, "export/index.html"),
      ".zeno-frame",
    )
  assert eventually(fn() {
    case cdp.loaded_fonts(page) {
      Ok(fonts) -> string.contains(fonts, "Settings Font normal")
      Error(_) -> False
    }
  })
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

/// A chart spec is drawn in the editor and in the page, and its switch shows
/// one row of panels at a time without any script.
pub fn a_charts_switch_shows_one_row_at_a_time_test() {
  let folder = harness.prepare("export-chart")
  let spec =
    "{\"kind\": \"lines\", \"x\": {\"label\": \"K\"}, \"y\": {\"label\": \"n\"},
\"grid\": {\"rows\": [\"paths\", \"queries\"], \"cols\": [\"a\"]},
\"panels\": [
{\"title\": \"a\", \"row\": \"paths\", \"col\": \"a\", \"series\": [{\"label\": \"s\", \"points\": [{\"x\": 1, \"y\": 2}, {\"x\": 2, \"y\": 4}]}]},
{\"title\": \"a\", \"row\": \"queries\", \"col\": \"a\", \"series\": [{\"label\": \"s\", \"points\": [{\"x\": 1, \"y\": 3}, {\"x\": 2, \"y\": 1}]}]}]}"
  let assert Ok(Nil) =
    simplifile.write(filepath.join(folder, "stats.json"), spec)
  let path = filepath.join(folder, "deck.md")
  let marker = "<!-- notes " <> harness.cell("04") <> " -->"
  let assert Ok(text) = simplifile.read(path)
  let assert Ok(Nil) =
    simplifile.write(
      path,
      string.replace(
        text,
        marker,
        "<!-- cell "
          <> harness.cell("ff")
          <> " -->\n![statistics](stats.json)\n\n"
          <> marker,
      ),
    )
  let #(page, _, _, _) = harness.open_folder(folder, 4955)
  assert eventually(fn() {
    cdp.count(page, ".ze-fit .zeno-chart-panel svg") == 2
  })
  press(page, "E")
  assert eventually(fn() { string.contains(status(page), "Exported to ") })
  let assert Ok(_) =
    cdp.open(
      page,
      "file://" <> filepath.join(folder, "export/index.html"),
      ".zeno-frame",
    )
  let display = fn(n) {
    cdp.computed(page, ".zeno-chart-row:nth-child(" <> n <> ")", "display")
  }
  assert display("1") == Ok("grid")
  assert display("2") == Ok("none")
  let assert Ok(_) =
    cdp.click(page, ".zeno-chart-switch > label:nth-of-type(2)")
  assert eventually(fn() { display("2") == Ok("grid") })
  assert display("1") == Ok("none")
}
