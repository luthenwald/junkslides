//// Serves the client bundle and answers Ping(n) with Pong(n + 1) over a
//// WebSocket at /ws.

import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/option.{None}
import mist.{type Connection, type ResponseData}
import shared/msg.{Ping, Pong}

pub fn main() -> Nil {
  let assert Ok(_) = start(4870, "../client/dist/")
  process.sleep_forever()
}

pub fn start(port: Int, static: String) {
  mist.new(handle(_, static))
  |> mist.bind("127.0.0.1")
  |> mist.port(port)
  |> mist.start
}

fn handle(req: Request(Connection), static: String) -> Response(ResponseData) {
  case request.path_segments(req) {
    ["ws"] ->
      mist.websocket(
        request: req,
        on_init: fn(_conn) { #(Nil, None) },
        on_close: fn(_state) { Nil },
        handler: on_message,
      )
    [] -> page()
    ["client.js"] -> file(static <> "client.js", "text/javascript")
    _ -> response.new(404) |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}

fn on_message(state, message, conn) {
  case message {
    mist.Text(text) ->
      case msg.decode(text) {
        Ok(Ping(n)) -> {
          let _ = mist.send_text_frame(conn, msg.encode(Pong(n + 1)))
          mist.continue(state)
        }
        _ -> mist.continue(state)
      }
    mist.Closed | mist.Shutdown -> mist.stop()
    _ -> mist.continue(state)
  }
}

fn page() -> Response(ResponseData) {
  let html =
    "<!doctype html><meta charset=utf-8><title>S3</title>"
    <> "<div id=app></div><script type=module src=/client.js></script>"
  response.new(200)
  |> response.set_header("content-type", "text/html")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(html)))
}

fn file(path: String, mime: String) -> Response(ResponseData) {
  case mist.send_file(path, offset: 0, limit: None) {
    Ok(body) ->
      response.new(200)
      |> response.set_header("content-type", mime)
      |> response.set_body(body)
    Error(_) ->
      response.new(404) |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}
