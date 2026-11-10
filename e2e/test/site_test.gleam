//// The site in `docs/` (`just site`), opened as GitHub Pages would serve
//// it: from a plain file server, under a subpath. `just e2e` builds it and
//// serves the project folder on port 9336.

import cdp
import gleam/string
import harness.{eventually, press, status}

const url = "http://127.0.0.1:9336/docs/"

/// The site as a first visit finds it: nothing kept by the browser.
fn opened() -> cdp.Page {
  let assert Ok(page) = cdp.connect(9334)
  let assert Ok(_) = cdp.viewport(page, 1280, 800)
  let assert Ok(_) = cdp.open(page, url, ".jse-selected")
  let assert Ok(_) = cdp.evaluate(page, "localStorage.clear(), 'cleared'")
  reload(page)
  page
}

fn reload(page: cdp.Page) -> Nil {
  let assert Ok(_) = cdp.open(page, "about:blank", "body")
  let assert Ok(_) = cdp.open(page, url, ".jse-selected")
  Nil
}

fn slide(page: cdp.Page) -> String {
  let assert Ok(html) = cdp.html(page, ".jse-fit .js-slide")
  html
}

fn choice(label: String) -> String {
  "button.jse-choice[title^=\"" <> label <> "\"]"
}

/// The editor runs on the showcase deck with no server: it draws the slide
/// with the deck's theme, takes an edit, undoes it, and hands the files
/// over as links. The exported slides are one folder down.
pub fn the_editor_runs_from_static_files_test() {
  let page = opened()
  let slide = fn() { slide(page) }
  assert string.contains(status(page), "edits are kept in this browser")
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

/// The browser keeps an edited deck across a reload, until you start over.
/// A folder you pick opens as a copy, with its own settings, theme and
/// drawings, and is kept too. The picker here hands over a folder in the
/// browser's own private file system, which reads as a folder on disk does.
pub fn edits_are_kept_and_a_folder_opens_test() {
  let page = opened()
  assert cdp.count(page, choice("Forgets")) == 0
  press(page, "Enter")
  let assert Ok(_) = cdp.type_text(page, " Kept here.")
  press(page, "Escape")
  assert eventually(fn() { string.contains(slide(page), "Kept here.") })
  reload(page)
  assert eventually(fn() { string.contains(slide(page), "Kept here.") })
  // Starting over forgets the edit, also after a reload.
  let assert Ok(_) = cdp.click(page, choice("Forgets your edits"))
  assert eventually(fn() { !string.contains(slide(page), "Kept here.") })
  reload(page)
  assert !string.contains(slide(page), "Kept here.")
  assert cdp.count(page, choice("Forgets")) == 0
  // A folder: deck.md, its settings and theme, and a drawing one folder down.
  let assert Ok(_) =
    cdp.evaluate(
      page,
      "window.showDirectoryPicker = async () => {
        const root = await navigator.storage.getDirectory();
        const talk = await root.getDirectoryHandle('talk', { create: true });
        const put = async (folder, name, text) => {
          const file = await folder.getFileHandle(name, { create: true });
          const stream = await file.createWritable();
          await stream.write(text);
          await stream.close();
        };
        await put(talk, 'deck.md', '# From a folder\\n\\n![](assets/fan.svg)\\n');
        await put(talk, 'junkslides.toml', '[palette]\\nbackground = \"#010203\"\\n');
        await put(talk, 'theme.css', '.js-slide h1 { color: rgb(4, 5, 6); }');
        const assets = await talk.getDirectoryHandle('assets', { create: true });
        await put(assets, 'fan.svg', '<svg class=\"mine\" viewBox=\"0 0 4 4\"><path d=\"M0,0 H4\"/></svg>');
        return talk;
      }, 'ready'",
    )
  let assert Ok(_) = cdp.click(page, choice("Works on a copy"))
  let is_the_copy = fn() {
    string.contains(status(page), "a copy of talk")
    && string.contains(slide(page), "From a folder")
    && cdp.count(page, ".jse-fit svg.mine") == 1
    && cdp.computed(page, ".jse-fit .js-slide", "background-color")
    == Ok("rgb(1, 2, 3)")
    && cdp.computed(page, ".jse-fit .js-slide h1", "color")
    == Ok("rgb(4, 5, 6)")
  }
  assert eventually(is_the_copy)
  assert cdp.count(page, "a[href=\"slides/\"]") == 0
  reload(page)
  assert eventually(is_the_copy)
  // Closing it brings the page's own deck back, with its own sheets.
  let assert Ok(_) = cdp.click(page, choice("Forgets this copy"))
  assert eventually(fn() {
    string.contains(status(page), "edits are kept in this browser")
    && string.contains(slide(page), "junkslides")
    && cdp.computed(page, ".jse-fit .js-slide", "background-color")
    == Ok("rgb(252, 252, 250)")
  })
  reload(page)
  assert string.contains(status(page), "edits are kept in this browser")
}

/// The slides beside it are the plain export, with no script.
pub fn the_slides_sit_one_folder_down_test() {
  let assert Ok(page) = cdp.connect(9334)
  let assert Ok(_) =
    cdp.open(page, "http://127.0.0.1:9336/docs/slides/", ".js-frame")
  assert cdp.count(page, ".js-frame") == 13
  assert cdp.count(page, "script") == 0
}
