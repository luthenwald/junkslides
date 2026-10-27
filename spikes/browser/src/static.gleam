//// Serves a folder over HTTP on 127.0.0.1 for the browser checks.

import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{None}
import gleam/string
import mist.{type Connection, type ResponseData}

pub fn serve(dir: String, port: Int) {
  mist.new(fn(req: Request(Connection)) {
    let path = case request.path_segments(req) {
      [] -> ["index.html"]
      segments -> segments
    }
    case list.contains(path, "..") {
      True -> not_found()
      False -> file(dir <> "/" <> string.join(path, "/"))
    }
  })
  |> mist.bind("127.0.0.1")
  |> mist.port(port)
  |> mist.start
}

fn file(path: String) -> Response(ResponseData) {
  case mist.send_file(path, offset: 0, limit: None) {
    Ok(body) ->
      response.new(200)
      |> response.set_header("content-type", mime(path))
      |> response.set_body(body)
    Error(_) -> not_found()
  }
}

fn mime(path: String) -> String {
  case string.split(path, ".") |> list.last {
    Ok("html") -> "text/html"
    Ok("js") | Ok("mjs") -> "text/javascript"
    Ok("css") -> "text/css"
    _ -> "application/octet-stream"
  }
}

fn not_found() -> Response(ResponseData) {
  response.new(404) |> response.set_body(mist.Bytes(bytes_tree.new()))
}
