//// HTTP and WebSocket (06-runtime.md, Protocol and Serving). `/ws` speaks
//// `zeno/protocol`; `/zeno/...` is the client bundle; every other path is a
//// file in the deck folder, such as theme.css and images.

import filepath
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/result
import gleam/string
import gleam/uri
import mist.{type Connection, type ResponseData}
import zeno/protocol.{type ServerMsg}
import zeno_server/state

pub type Config {
  Config(port: Int, folder: String, client: String)
}

pub fn start(
  config: Config,
  owner: Subject(state.Message),
) -> Result(actor.Started(static_supervisor.Supervisor), actor.StartError) {
  mist.new(handle(_, config, owner))
  |> mist.bind("127.0.0.1")
  |> mist.port(config.port)
  |> mist.start
}

fn handle(
  req: Request(Connection),
  config: Config,
  owner: Subject(state.Message),
) -> Response(ResponseData) {
  case request.path_segments(req) {
    ["ws"] -> socket(req, owner)
    [] -> page()
    ["zeno", ..rest] -> serve(config.client, rest)
    segments -> serve(config.folder, segments)
  }
}

fn socket(
  req: Request(Connection),
  owner: Subject(state.Message),
) -> Response(ResponseData) {
  mist.websocket(
    request: req,
    on_init: fn(_conn) {
      let client = process.new_subject()
      process.send(owner, state.Join(client))
      #(client, Some(process.new_selector() |> process.select(client)))
    },
    on_close: fn(client) { process.send(owner, state.Leave(client)) },
    handler: fn(client: Subject(ServerMsg), message, conn) {
      case message {
        mist.Text(text) -> {
          case protocol.decode_client(text) {
            Ok(msg) -> process.send(owner, state.FromClient(client, msg))
            Error(_) -> {
              let notice =
                protocol.Notice("The server did not understand a message.")
              let _ = mist.send_text_frame(conn, protocol.encode_server(notice))
              Nil
            }
          }
          mist.continue(client)
        }
        mist.Custom(msg) -> {
          let _ = mist.send_text_frame(conn, protocol.encode_server(msg))
          mist.continue(client)
        }
        mist.Binary(_) -> mist.continue(client)
        mist.Closed | mist.Shutdown -> mist.stop()
      }
    },
  )
}

/// The client bundle is built in M3; until then the page loads nothing but
/// the theme.
fn page() -> Response(ResponseData) {
  let html =
    "<!doctype html>\n<meta charset=utf-8>\n<title>Zeno</title>\n"
    <> "<link rel=stylesheet href=/theme.css>\n<div id=app></div>\n"
    <> "<script type=module src=/zeno/client.js></script>\n"
  response.new(200)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(html)))
}

fn serve(root: String, segments: List(String)) -> Response(ResponseData) {
  let file = {
    use relative <- result.try(resolve(segments))
    let path = filepath.join(root, relative)
    mist.send_file(path, offset: 0, limit: None)
    |> result.replace_error(Nil)
    |> result.map(fn(body) { #(relative, body) })
  }
  case file {
    Ok(#(relative, body)) ->
      response.new(200)
      |> response.set_header("content-type", content_type(relative))
      |> response.set_header("cache-control", "no-cache")
      |> response.set_body(body)
    Error(Nil) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
  }
}

/// A relative path that stays inside the folder it is joined to. Segments
/// are percent-decoded first, then checked: no empty, `.` or `..` segments,
/// no hidden files (such as the temporary files of atomic writes), no
/// separators or NUL inside a segment.
pub fn resolve(segments: List(String)) -> Result(String, Nil) {
  use segments <- result.try(list.try_map(segments, uri.percent_decode))
  let allowed = fn(segment) {
    segment != ""
    && !string.starts_with(segment, ".")
    && !string.contains(segment, "/")
    && !string.contains(segment, "\\")
    && !string.contains(segment, "\u{0}")
  }
  case segments != [] && list.all(segments, allowed) {
    True -> Ok(string.join(segments, "/"))
    False -> Error(Nil)
  }
}

fn content_type(path: String) -> String {
  case filepath.extension(path) |> result.map(string.lowercase) {
    Ok("html") -> "text/html; charset=utf-8"
    Ok("css") -> "text/css; charset=utf-8"
    Ok("js") | Ok("mjs") -> "text/javascript; charset=utf-8"
    Ok("json") -> "application/json"
    Ok("md") | Ok("txt") -> "text/plain; charset=utf-8"
    Ok("png") -> "image/png"
    Ok("jpg") | Ok("jpeg") -> "image/jpeg"
    Ok("gif") -> "image/gif"
    Ok("svg") -> "image/svg+xml"
    Ok("webp") -> "image/webp"
    Ok("avif") -> "image/avif"
    _ -> "application/octet-stream"
  }
}
