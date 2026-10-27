//// Per-user view state (05-editor.md, View state; P15): pane sizes and
//// hidden panes, stored by the server in one file for all decks, keyed by
//// the deck folder's absolute path.

import filepath
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile
import zeno/codec.{Num, Obj}
import zeno/protocol.{type View}
import zeno_server/store

/// `~/.config/zeno/view.json` (P15).
pub fn default_file(home: String) -> String {
  filepath.join(home, ".config/zeno/view.json")
}

/// The stored view for a deck, or the default view. A missing or unreadable
/// file counts as empty.
pub fn load(file: String, deck: String) -> View {
  read_all(file)
  |> dict.get(deck)
  |> result.unwrap(protocol.default_view)
}

/// Stores the view for a deck, keeping the views of other decks.
pub fn save(file: String, deck: String, view: View) -> Result(Nil, String) {
  let views = read_all(file) |> dict.insert(deck, view)
  let value =
    Obj([
      #("version", Num(1)),
      #(
        "decks",
        dict.to_list(views)
          |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
          |> list.map(fn(entry) { #(entry.0, protocol.view_value(entry.1)) })
          |> Obj,
      ),
    ])
  use Nil <- result.try(
    simplifile.create_directory_all(filepath.directory_name(file))
    |> result.map_error(simplifile.describe_error),
  )
  store.write_atomic(file, bit_array.from_string(codec.pretty(value)))
  |> result.replace(Nil)
}

fn read_all(file: String) -> Dict(String, View) {
  let decoder = {
    use decks <- decode.field(
      "decks",
      decode.dict(decode.string, protocol.view_decoder()),
    )
    decode.success(decks)
  }
  simplifile.read(file)
  |> result.replace_error(Nil)
  |> result.try(fn(text) {
    json.parse(text, decoder) |> result.replace_error(Nil)
  })
  |> result.unwrap(dict.new())
}
