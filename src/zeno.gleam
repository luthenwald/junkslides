//// The `zeno` command, run from the root of the source tree:
////
////     gleam run init <folder>
////     gleam run serve <folder> [--port N]
////     gleam run export <folder> [--out path] [--pdf]
////
//// Before serving, the editor is bundled from client/ into the server's
//// priv/static, as `just client` does, so the page always matches the source.
//// Relative folders are read from where `gleam run` is started.

import argv
import filepath
import gleam/io
import gleam/result
import shellout
import simplifile
import zeno_server

pub fn main() -> Nil {
  let bundled = case argv.load().arguments {
    ["serve", ..] -> bundle_client()
    _ -> Ok(Nil)
  }
  case bundled {
    Ok(Nil) -> zeno_server.main()
    Error(message) -> {
      io.println_error(message)
      halt(1)
    }
  }
}

/// Builds the client bundle when its source is in the tree `gleam run` was
/// started in, and does nothing otherwise, as in an exported shipment.
fn bundle_client() -> Result(Nil, String) {
  let root =
    simplifile.current_directory()
    |> result.replace_error(Nil)
    |> result.try(source_root)
  case root {
    Error(_) -> Ok(Nil)
    Ok(root) ->
      shellout.command(
        run: "gleam",
        with: [
          "run", "-m", "lustre/dev", "build", "--outdir=../server/priv/static",
          "--no-html", "--minify",
        ],
        in: filepath.join(root, "client"),
        opt: [],
      )
      |> result.replace(Nil)
      |> result.map_error(fn(failed) {
        "Could not bundle the editor from client/:\n" <> failed.1
      })
  }
}

/// The nearest folder at or above `folder` holding this package and the
/// client's source. `gleam run` works from any folder inside the project and
/// keeps that folder as the working directory.
fn source_root(folder: String) -> Result(String, Nil) {
  let here = fn(name) { simplifile.is_file(filepath.join(folder, name)) }
  case here("gleam.toml"), here("client/gleam.toml") {
    Ok(True), Ok(True) -> Ok(folder)
    _, _ ->
      case filepath.directory_name(folder) {
        parent if parent == folder || parent == "" -> Error(Nil)
        parent -> source_root(parent)
      }
  }
}

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil
