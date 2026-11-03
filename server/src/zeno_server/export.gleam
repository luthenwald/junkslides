//// Writes a deck as a static folder (04-layout.md, Export): `index.html` from
//// `render.document`, `settings.css` from zeno.toml and the fonts it names, a
//// copy of theme.css and the files it loads, such as its fonts, and the deck's
//// images, and on request a PDF of the page. Of the deck, it only reads the
//// folder. Nothing is deleted, and files outside the deck are never copied in,
//// so a shared export holds only what belongs to the talk.

import filepath
import gleam/bit_array
import gleam/bool
import gleam/dict
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
import zeno_server/figures
import zeno_server/highlighter
import zeno_server/pdf
import zeno_server/settings.{type Settings}
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
  use settings <- result.try(read_settings(folder))
  use Nil <- result.try(
    simplifile.create_directory_all(out) |> result.map_error(describe(out, _)),
  )
  use Nil <- result.try(copy_assets(folder, out))
  use theme_bytes <- result.try(read_theme(folder))
  let settings_css =
    settings
    |> option.map(settings.to_css(_, ""))
    |> option.unwrap("")
  let #(fonts, settings_warnings) =
    settings
    |> option.map(settings_files(folder, _))
    |> option.unwrap(#([], []))
  let #(images, image_warnings) = images_to_copy(folder, deck)
  let #(loaded, theme_warnings) =
    theme_bytes
    |> option.map(bit_array.to_string)
    |> option.map(result.unwrap(_, ""))
    |> option.map(theme_files(folder, _))
    |> option.unwrap(#([], []))
  let has_settings = settings_css != ""
  let clash = case has_settings && list.contains(loaded, "settings.css") {
    True -> [
      "theme.css loads settings.css, which the export writes from zeno.toml.",
    ]
    False -> []
  }
  let warnings =
    list.flatten([image_warnings, settings_warnings, theme_warnings, clash])
  let fonts_and_loaded = list.append(fonts, loaded)
  use Nil <- result.try(
    list.flatten([
      images,
      fonts_and_loaded,
      licences_beside(folder, fonts_and_loaded),
    ])
    |> list.unique
    |> list.try_each(copy(folder, out, _)),
  )
  use Nil <- result.try(case has_settings {
    False -> Ok(Nil)
    True ->
      store.write_atomic(
        filepath.join(out, "settings.css"),
        bit_array.from_string(settings_css),
      )
      |> result.replace(Nil)
  })
  let has_theme = option.is_some(theme_bytes)
  use Nil <- result.try(case theme_bytes {
    None -> Ok(Nil)
    Some(bytes) ->
      store.write_atomic(filepath.join(out, "theme.css"), bytes)
      |> result.replace(Nil)
  })
  let highlights =
    highlighter.highlight(
      tree_sitter,
      protocol.code_blocks(deck),
      settings.keywords(settings),
    )
    |> list.map(fn(highlight) { #(highlight.block, highlight.tokens) })
    |> dict.from_list
  let figure_files =
    protocol.figures(deck)
    |> list.map(fn(url) { #(url, figures.read(folder, url)) })
  let figure_warnings =
    list.filter_map(figure_files, fn(pair) { figures.problem(pair.0, pair.1) })
  let figures =
    figures.usable(figure_files)
    |> dict.from_list
  let page = filepath.join(out, "index.html")
  let html =
    render.document(
      deck:,
      layout:,
      highlights:,
      figures:,
      title: filepath.base_name(folder),
      has_settings:,
      has_theme:,
    )
  use _ <- result.try(store.write_atomic(page, bit_array.from_string(html)))
  Ok(Report(page, list.append(warnings, figure_warnings)))
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

/// The deck's zeno.toml, if it has one. One that does not read stops the
/// export, as a broken deck does, rather than giving pages in other fonts.
fn read_settings(folder: String) -> Result(Option(Settings), String) {
  let path = filepath.join(folder, "zeno.toml")
  case simplifile.is_file(path) {
    Ok(True) -> {
      use text <- result.try(
        simplifile.read(path) |> result.map_error(describe(path, _)),
      )
      settings.parse(text) |> result.map(Some)
    }
    _ -> Ok(None)
  }
}

/// The font files zeno.toml names, and the warnings about missing ones. The
/// export's settings.css sits at its root and names them by the same relative
/// paths.
fn settings_files(
  folder: String,
  settings: Settings,
) -> #(List(String), List(String)) {
  settings.files(settings)
  |> list.map(locate(
    folder,
    _,
    missing: "Missing file in zeno.toml: ",
    outside: "Left out a file outside the deck in zeno.toml: ",
  ))
  |> split_results
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
/// a file.
fn theme_files(folder: String, css: String) -> #(List(String), List(String)) {
  theme.urls(css)
  |> list.map(fn(url) {
    case url {
      "/" <> _ -> Error("Use a relative path in theme.css: " <> url)
      _ ->
        locate(
          folder,
          without_dot_segments(url),
          missing: "Missing file in theme.css: ",
          outside: "Left out a file outside the deck in theme.css: ",
        )
    }
  })
  |> split_results
}

/// The licence files in the folders of the given files, so that a font's
/// licence travels with it: names with `LICENSE` or `LICENCE` in them, in any
/// case, apart from hidden ones.
fn licences_beside(folder: String, files: List(String)) -> List(String) {
  files
  |> list.map(filepath.directory_name)
  |> list.unique
  |> list.flat_map(fn(directory) {
    simplifile.read_directory(filepath.join(folder, directory))
    |> result.unwrap([])
    |> list.filter(fn(name) {
      let upper = string.uppercase(name)
      !string.starts_with(name, ".")
      && {
        string.contains(upper, "LICENSE") || string.contains(upper, "LICENCE")
      }
    })
    |> list.map(fn(name) {
      case directory {
        "" -> name
        _ -> directory <> "/" <> name
      }
    })
    |> list.filter(fn(relative) {
      simplifile.is_file(filepath.join(folder, relative)) == Ok(True)
    })
  })
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
