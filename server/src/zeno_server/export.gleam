//// Writes a deck as a static folder (04-layout.md, Export): `index.html` from
//// `render.document`, a copy of theme.css, and the deck's images. It only reads
//// the deck folder. Nothing is deleted, and files outside the deck are never
//// copied in, so a shared export holds only what belongs to the talk.

import filepath
import gleam/bit_array
import gleam/bool
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import simplifile
import zeno/deck.{type Deck}
import zeno/dialect
import zeno/layout.{type Layout}
import zeno/protocol
import zeno/render
import zeno_server/highlighter
import zeno_server/store

pub type Report {
  /// `page` is the path of the written page; `warnings` name images that
  /// could not be included.
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
  use Nil <- result.try(
    simplifile.create_directory_all(out) |> result.map_error(describe(out, _)),
  )
  use Nil <- result.try(copy_assets(folder, out))
  let #(images, warnings) = images_to_copy(folder, deck)
  use Nil <- result.try(list.try_each(images, copy(folder, out, _)))
  let theme = filepath.join(folder, "theme.css")
  let has_theme = simplifile.is_file(theme) == Ok(True)
  use Nil <- result.try(case has_theme {
    False -> Ok(Nil)
    True -> {
      use bytes <- result.try(
        simplifile.read_bits(theme) |> result.map_error(describe(theme, _)),
      )
      store.write_atomic(filepath.join(out, "theme.css"), bytes)
      |> result.replace(Nil)
    }
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

/// The relative paths of the images drawn cells use beyond `assets/`, and the
/// warnings about those that are missing or lead out of the deck.
fn images_to_copy(folder: String, deck: Deck) -> #(List(String), List(String)) {
  let results =
    deck.slides
    |> list.flat_map(render.drawn_cells)
    |> list.flat_map(fn(cell) { dialect.images(cell.source) })
    |> list.unique
    |> list.map(fn(image) { locate(folder, image) })
  #(result.values(results), result.partition(results).1 |> list.reverse)
}

fn locate(folder: String, image: String) -> Result(String, String) {
  let path = strip_suffix(strip_suffix(image, "#"), "?")
  case store.resolve(string.split(path, "/")) {
    Error(Nil) -> Error("Left out an image outside the deck: " <> image)
    Ok(relative) ->
      case simplifile.is_file(filepath.join(folder, relative)) {
        Ok(True) -> Ok(relative)
        _ -> Error("Missing image: " <> image)
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
