//// HTTP and WebSocket (06-runtime.md, Protocol and Serving). `/.zeno/ws`
//// speaks `zeno/protocol`; `/.zeno/...` is the client bundle and base styles; every other
//// path is a file in the deck folder, such as theme.css and images. Deck
//// files never start with a dot, so the editor's own paths cannot hide one.

import filepath
import gleam/bool
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/result
import gleam/string
import mist.{type Connection, type ResponseData}
import zeno/protocol.{type ServerMsg}
import zeno/render/styles
import zeno_server/state
import zeno_server/store

pub type Config {
  Config(port: Int, folder: String, client: String, fonts: String)
}

pub fn start(
  config: Config,
  owner: Subject(state.Message),
) -> Result(actor.Started(static_supervisor.Supervisor), actor.StartError) {
  mist.new(handle(_, config, owner))
  |> mist.bind("127.0.0.1")
  |> mist.port(config.port)
  // `zeno serve` says where it listens itself.
  |> mist.after_start(fn(_, _, _) { Nil })
  |> mist.start
}

fn handle(
  req: Request(Connection),
  config: Config,
  owner: Subject(state.Message),
) -> Response(ResponseData) {
  use <- bool.lazy_guard(!trusted(req, config.port), refused)
  case request.path_segments(req) {
    [] -> page()
    [".zeno", "ws"] ->
      case same_origin(req, config.port) {
        True -> socket(req, owner)
        False -> refused()
      }
    [".zeno", "base.css"] -> base_styles()
    [".zeno", "settings.css"] -> settings_styles(owner)
    [".zeno", "fonts", ..rest] -> serve(config.fonts, rest)
    [".zeno", ..rest] -> serve(config.client, rest)
    segments -> serve(config.folder, segments)
  }
}

/// The names the server answers to. Checking the host keeps out a name that
/// resolves to this machine (DNS rebinding), which would make another site
/// the same origin as the editor.
fn local(port: Int) -> List(String) {
  ["127.0.0.1:" <> int.to_string(port), "localhost:" <> int.to_string(port)]
}

/// A request to this server by a name it listens on.
pub fn trusted(req: Request(a), port: Int) -> Bool {
  case request.get_header(req, "host") {
    Ok(host) -> list.contains(local(port), host)
    Error(Nil) -> False
  }
}

/// A socket the editor's own page could have opened: browsers let any page
/// open a WebSocket to any address and say where it comes from, and an
/// embedded page's script runs inside the editor (D29), so the socket that
/// edits the deck is closed to other origins, sandboxed frames (`null`)
/// among them. Clients that are not browsers send no origin.
pub fn same_origin(req: Request(a), port: Int) -> Bool {
  case request.get_header(req, "origin") {
    Error(Nil) -> True
    Ok(origin) ->
      list.contains(list.map(local(port), fn(l) { "http://" <> l }), origin)
  }
}

fn refused() -> Response(ResponseData) {
  response.new(403)
  |> response.set_body(mist.Bytes(bytes_tree.from_string("Forbidden")))
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

/// The page: the editor's styles and the client bundle (`just client`
/// builds both into priv/static). The client links the deck's theme
/// itself, so that it can reload it.
fn page() -> Response(ResponseData) {
  let html =
    "<!doctype html>\n<meta charset=utf-8>\n<title>Zeno</title>\n"
    <> "<link rel=stylesheet href=/.zeno/base.css>\n"
    <> "<link rel=stylesheet href=/.zeno/zeno.css>\n<div id=app></div>\n"
    <> "<script type=module src=/.zeno/zeno_client.js></script>\n"
  response.new(200)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(html)))
}

/// The slide's base styles, shared with export.
fn base_styles() -> Response(ResponseData) {
  response.new(200)
  |> response.set_header("content-type", "text/css; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(styles.base_css)))
}

/// The deck's settings from zeno.toml, between the base styles and the theme
/// (04-layout.md, Stylesheets). The client links it with the theme.
fn settings_styles(owner: Subject(state.Message)) -> Response(ResponseData) {
  response.new(200)
  |> response.set_header("content-type", "text/css; charset=utf-8")
  |> response.set_header("cache-control", "no-cache")
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string(state.settings_css(owner))),
  )
}

fn serve(root: String, segments: List(String)) -> Response(ResponseData) {
  let file = {
    use relative <- result.try(store.resolve(segments))
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
    Ok("woff2") -> "font/woff2"
    _ -> "application/octet-stream"
  }
}
