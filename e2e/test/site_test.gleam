//// The site in `docs/` (`just site`), opened as GitHub Pages would serve
//// it: from a plain file server, under a subpath. `just e2e` builds it and
//// serves the project folder on port 9336.

import cdp
import gleam/string
import harness.{eventually, press, status}

fn opened() -> cdp.Page {
  let assert Ok(page) = cdp.connect(9334)
  let assert Ok(_) = cdp.viewport(page, 1280, 800)
  let assert Ok(_) =
    cdp.open(page, "http://127.0.0.1:9336/docs/", ".jse-selected")
  page
}

/// The editor runs on the showcase deck with no server: it draws the slide
/// with the deck's theme, takes an edit, undoes it, and hands the files
/// over as links. The exported slides are one folder down.
pub fn the_editor_runs_from_static_files_test() {
  let page = opened()
  let slide = fn() {
    let assert Ok(html) = cdp.html(page, ".jse-fit .js-slide")
    html
  }
  assert string.contains(status(page), "edits stay in this page")
  assert string.contains(status(page), "01/13")
  // The deck's own sheets load from beside the page, under the subpath.
  assert eventually(fn() {
    cdp.computed(page, ".jse-fit .js-slide", "background-color")
    == Ok("rgb(252, 252, 250)")
  })
  assert eventually(fn() {
    case cdp.loaded_fonts(page) {
      Ok(fonts) -> string.contains(fonts, "et-book normal")
      Error(_) -> False
    }
  })
  // The first slide has its number switched off; `n` shows it again.
  assert cdp.computed(page, ".jse-fit .js-page", "display") == Ok("none")
  press(page, "n")
  assert eventually(fn() {
    cdp.computed(page, ".jse-fit .js-page", "display") == Ok("block")
  })
  // Typing reaches the drawn slide, and undo takes it back.
  press(page, "Enter")
  let assert Ok(_) = cdp.type_text(page, " Typed here.")
  assert eventually(fn() { string.contains(slide(), "Typed here.") })
  press(page, "Escape")
  press(page, "u")
  assert eventually(fn() { !string.contains(slide(), "Typed here.") })
  // A drawing and a chart came with the page.
  press(page, "}")
  assert eventually(fn() { cdp.count(page, ".jse-fit svg.folder") == 1 })
  // `E` offers the two files, as they are now.
  press(page, "E")
  assert eventually(fn() { cdp.count(page, "a.jse-download[download]") == 2 })
  let assert Ok(href) = cdp.attribute(page, "a[download=\"deck.md\"]", "href")
  assert string.starts_with(href, "data:text/plain;charset=utf-8,")
  assert string.contains(href, "junkslides%2C%20a%20slide%20maker")
  assert !string.contains(href, "Typed")
  assert cdp.count(page, "a[href=\"slides/\"]") == 1
}

/// The slides beside it are the plain export, with no script.
pub fn the_slides_sit_one_folder_down_test() {
  let assert Ok(page) = cdp.connect(9334)
  let assert Ok(_) =
    cdp.open(page, "http://127.0.0.1:9336/docs/slides/", ".js-frame")
  assert cdp.count(page, ".js-frame") == 13
  assert cdp.count(page, "script") == 0
}
