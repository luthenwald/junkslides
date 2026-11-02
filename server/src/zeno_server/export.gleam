//// Writes a deck as a static folder (04-layout.md, Export): `index.html` from
//// `render.document`, a copy of theme.css and the files it loads, the deck's
//// images, and the default fonts, and on request a PDF of the page. Of the deck, it only reads the
//// folder. Nothing is deleted, and files outside the deck are never copied in,
//// so a shared export holds only what belongs to the talk.

import filepath
import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/erlang/application
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile
import zeno/deck.{type Deck}
import zeno/dialect
import zeno/layout.{type Layout}
import zeno/protocol
import zeno/render
import zeno_server/highlighter
import zeno_server/pdf
import zeno_server/store
import zeno_server/theme

pub type Report {
  /// `page` is the path of the written page or PDF; `warnings` name images
  /// and files of the theme that could not be included.
  Report(page: String, warnings: List(String))
}

/// Where an export goes unless told otherwise: `export/` in the deck folder.
pub fn default_out(folder: String) -> String {
  filepath.join(folder, "export")
}

/// The default fonts and their licences, which ship with Zeno in `priv/fonts`.
pub fn fonts_folder() -> Result(String, String) {
  application.priv_directory("zeno_server")
  |> result.map(filepath.join(_, "fonts"))
  |> result.replace_error("The zeno_server priv folder is missing.")
}

/// Exports to the folder `out`. Both paths are absolute and expanded.
/// `tree_sitter` is the command that highlights code blocks.
pub fn write(
  folder folder: String,
  out out: String,
  deck deck: Deck,
  layout layout: Layout,
  tree_sitter tree_sitter: String,
) -> Result(Report, String) {
  use Nil <- result.try(check_out(folder, out))
  use Nil <- result.try(
    simplifile.create_directory_all(out) |> result.map_error(describe(out, _)),
  )
  use defaults <- result.try(default_fonts())
  use Nil <- result.try(copy_fonts(out, defaults))
  use Nil <- result.try(copy_assets(folder, out))
  use theme_bytes <- result.try(read_theme(folder))
  let #(images, image_warnings) = images_to_copy(folder, deck)
  let #(loaded, theme_warnings) =
    theme_bytes
    |> option.map(bit_array.to_string)
    |> option.map(result.unwrap(_, ""))
    |> option.map(theme_files(folder, _, defaults))
    |> option.unwrap(#([], []))
  let warnings = list.append(image_warnings, theme_warnings)
  use Nil <- result.try(
    list.append(images, loaded)
    |> list.unique
    |> list.try_each(copy(folder, out, _)),
  )
  let has_theme = option.is_some(theme_bytes)
  use Nil <- result.try(case theme_bytes {
    None -> Ok(Nil)
    Some(bytes) ->
      store.write_atomic(filepath.join(out, "theme.css"), bytes)
      |> result.replace(Nil)
  })
  let highlights =
    highlighter.highlight(tree_sitter, protocol.code_blocks(deck))
    |> list.map(fn(highlight) { #(highlight.block, highlight.tokens) })
    |> dict.from_list
  let page = filepath.join(out, "index.html")
  let html =
    render.document(
      deck:,
      layout:,
      highlights:,
      title: filepath.base_name(folder),
      has_theme:,
    )
  use _ <- result.try(store.write_atomic(page, bit_array.from_string(html)))
  Ok(Report(page, warnings))
}

/// Exports to the folder `out`, and prints the page to a PDF there, named after
/// the deck. `browser` is the program that prints it (`pdf.find`).
pub fn write_pdf(
  folder folder: String,
  out out: String,
  deck deck: Deck,
  layout layout: Layout,
  tree_sitter tree_sitter: String,
  browser browser: String,
) -> Result(Report, String) {
  use Report(page:, warnings:) <- result.try(write(
    folder:,
    out:,
    deck:,
    layout:,
    tree_sitter:,
  ))
  let target = filepath.join(out, filepath.base_name(folder) <> ".pdf")
  use Nil <- result.try(pdf.print(page:, target:, browser:))
  Ok(Report(target, warnings))
}

/// The deck folder would get an `index.html` among its own files, and a folder
/// in `assets/` would be copied into itself.
fn check_out(folder: String, out: String) -> Result(Nil, String) {
  let assets = filepath.join(folder, "assets")
  use <- bool.guard(
    out == folder,
    Error("Export to a folder of its own, not to the deck's folder."),
  )
  use <- bool.guard(
    out == assets || string.starts_with(out, assets <> "/"),
    Error("Export to a folder outside the deck's assets."),
  )
  Ok(Nil)
}

/// The names of the files in the fonts folder.
fn default_fonts() -> Result(List(String), String) {
  use fonts <- result.try(fonts_folder())
  simplifile.read_directory(fonts) |> result.map_error(describe(fonts, _))
}

/// The default fonts, into `fonts/`, where the base styles look.
fn copy_fonts(out: String, files: List(String)) -> Result(Nil, String) {
  let target = filepath.join(out, "fonts")
  use fonts <- result.try(fonts_folder())
  use Nil <- result.try(
    simplifile.create_directory_all(target)
    |> result.map_error(describe(target, _)),
  )
  list.try_each(files, fn(file) {
    let path = filepath.join(target, file)
    simplifile.copy_file(filepath.join(fonts, file), path)
    |> result.map_error(describe(path, _))
  })
}

/// Every file in `assets/`, apart from hidden ones.
fn copy_assets(folder: String, out: String) -> Result(Nil, String) {
  let assets = filepath.join(folder, "assets")
  case simplifile.is_directory(assets) {
    Ok(True) -> {
      use files <- result.try(
        simplifile.get_files(assets) |> result.map_error(describe(assets, _)),
      )
      files
      |> list.map(string.drop_start(_, string.length(folder) + 1))
      |> list.filter(fn(relative) {
        !list.any(string.split(relative, "/"), string.starts_with(_, "."))
      })
      |> list.try_each(copy(folder, out, _))
    }
    _ -> Ok(Nil)
  }
}

/// The deck's theme.css, if it has one. It is copied as it is; a theme that is
/// not UTF-8 is not read for paths.
fn read_theme(folder: String) -> Result(Option(BitArray), String) {
  let path = filepath.join(folder, "theme.css")
  case simplifile.is_file(path) {
    Ok(True) ->
      simplifile.read_bits(path)
      |> result.map(Some)
      |> result.map_error(describe(path, _))
    _ -> Ok(None)
  }
}

/// The relative paths of the images drawn cells use beyond `assets/`, and the
/// warnings about those that are missing or lead out of the deck.
fn images_to_copy(folder: String, deck: Deck) -> #(List(String), List(String)) {
  deck.slides
  |> list.flat_map(render.drawn_cells)
  |> list.flat_map(fn(cell) { dialect.images(cell.source) })
  |> list.unique
  |> list.map(fn(image) {
    locate(
      folder,
      image,
      missing: "Missing image: ",
      outside: "Left out an image outside the deck: ",
    )
  })
  |> split_results
}

/// The relative paths of the files theme.css loads with `url()`, and the
/// warnings about those that cannot be included. The page reads theme.css
/// from the export's root, as the editor does from the deck's, so a relative
/// path finds the copy. A path from the root works in the editor but not from
/// a file, and a file named like a default font would take that font's place
/// in the export but not in the editor.
fn theme_files(
  folder: String,
  css: String,
  defaults: List(String),
) -> #(List(String), List(String)) {
  theme.urls(css)
  |> list.map(fn(url) {
    case url {
      "/" <> _ -> Error("Use a relative path in theme.css: " <> url)
      _ -> {
        use relative <- result.try(locate(
          folder,
          without_dot_segments(url),
          missing: "Missing file in theme.css: ",
          outside: "Left out a file outside the deck in theme.css: ",
        ))
        case list.any(defaults, fn(font) { relative == "fonts/" <> font }) {
          True ->
            Error(
              "Rename this file in theme.css, a default font has its name: "
              <> url,
            )
          False -> Ok(relative)
        }
      }
    }
  })
  |> split_results
}

fn without_dot_segments(path: String) -> String {
  case path {
    "./" <> rest -> without_dot_segments(rest)
    path -> path
  }
}

fn split_results(results: List(Result(a, b))) -> #(List(a), List(b)) {
  #(result.values(results), result.partition(results).1 |> list.reverse)
}

fn locate(
  folder: String,
  url: String,
  missing missing: String,
  outside outside: String,
) -> Result(String, String) {
  let path = strip_suffix(strip_suffix(url, "#"), "?")
  case store.resolve(string.split(path, "/")) {
    Error(Nil) -> Error(outside <> url)
    Ok(relative) ->
      case simplifile.is_file(filepath.join(folder, relative)) {
        Ok(True) -> Ok(relative)
        _ -> Error(missing <> url)
      }
  }
}

fn strip_suffix(path: String, mark: String) -> String {
  case string.split_once(path, mark) {
    Ok(#(before, _)) -> before
    Error(Nil) -> path
  }
}

fn copy(folder: String, out: String, relative: String) -> Result(Nil, String) {
  let target = filepath.join(out, relative)
  use Nil <- result.try(
    simplifile.create_directory_all(filepath.directory_name(target))
    |> result.map_error(describe(target, _)),
  )
  simplifile.copy_file(filepath.join(folder, relative), target)
  |> result.map_error(describe(target, _))
}

fn describe(path: String, error: simplifile.FileError) -> String {
  "Could not export to " <> path <> ": " <> simplifile.describe_error(error)
}
