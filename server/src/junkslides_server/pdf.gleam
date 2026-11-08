//// Prints an exported page to a PDF with a Chromium browser in headless mode
//// (04-layout.md, Export; D26). The page's print styles decide the pages, so
//// the PDF is what printing it by hand gives. The browser writes in a temporary
//// folder, and only a file that is a PDF reaches the target, atomically.

import envoy
import filepath
import gleam/bit_array
import gleam/crypto
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import gleam/uri
import junkslides_server/store
import shellout
import simplifile

const commands = [
  "chromium", "chromium-browser", "google-chrome", "google-chrome-stable",
  "microsoft-edge", "brave-browser",
]

const applications = [
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
]

/// The browser to print with: `JUNKSLIDES_CHROME` if it is set, or else the first one
/// found among the usual commands and applications.
pub fn find() -> Result(String, String) {
  case envoy.get("JUNKSLIDES_CHROME") {
    Ok(path) if path != "" ->
      shellout.which(path)
      |> result.replace_error("JUNKSLIDES_CHROME names no program: " <> path)
    _ ->
      list.append(commands, applications)
      |> list.find_map(shellout.which)
      |> result.replace_error(
        "A PDF needs Chrome, Chromium, Edge or Brave, and none was found. Install one, or set JUNKSLIDES_CHROME to its program.",
      )
  }
}

/// Prints the page at the absolute path `page` to `target`. On any failure the
/// target stays as it was.
pub fn print(
  page page: String,
  target target: String,
  browser browser: String,
) -> Result(Nil, String) {
  let scratch = temporary_folder()
  let outcome = {
    use Nil <- result.try(
      simplifile.create_directory_all(scratch)
      |> result.map_error(fn(error) {
        "Could not make the PDF: " <> simplifile.describe_error(error)
      }),
    )
    let printed = filepath.join(scratch, "printed.pdf")
    use _ <- result.try(
      shellout.command(
        run: browser,
        with: arguments(page, printed, scratch),
        in: scratch,
        opt: [],
      )
      |> result.map_error(browser_failed),
    )
    use bytes <- result.try(
      simplifile.read_bits(printed)
      |> result.replace_error("The browser did not write a PDF."),
    )
    case bytes {
      <<"%PDF-":utf8, _:bits>> ->
        store.write_atomic(target, bytes) |> result.replace(Nil)
      _ -> Error("The browser wrote something that is not a PDF.")
    }
  }
  let _ = simplifile.delete(scratch)
  outcome
}

/// A profile of its own, so a browser that is already open neither takes the
/// job over nor sees it. The time budget lets the page's fonts arrive.
fn arguments(page: String, printed: String, profile: String) -> List(String) {
  [
    "--headless",
    "--no-first-run",
    "--no-default-browser-check",
    "--no-pdf-header-footer",
    "--virtual-time-budget=10000",
    "--user-data-dir=" <> profile,
    "--print-to-pdf=" <> printed,
    file_url(page),
  ]
}

/// The address of a file at an absolute path. Spaces and `#` are common in
/// folder names, and would break the address as they are.
pub fn file_url(path: String) -> String {
  let encoded =
    string.split(path, "/")
    |> list.map(uri.percent_encode)
    |> string.join("/")
  "file://" <> encoded
}

fn browser_failed(failure: #(Int, String)) -> String {
  let #(code, output) = failure
  let detail = case string.trim(output) {
    "" -> ""
    output -> ": " <> output
  }
  "The browser stopped with code " <> int.to_string(code) <> detail
}

fn temporary_folder() -> String {
  let suffix = crypto.strong_random_bytes(8) |> bit_array.base16_encode
  envoy.get("TMPDIR")
  |> result.unwrap("/tmp")
  |> filepath.join("js-pdf-" <> suffix)
}
