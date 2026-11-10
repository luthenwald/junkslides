//// HTTP and WebSocket (06-runtime.md, Protocol and Serving). `/.js/ws`
//// speaks `junkslides/protocol`; `/.js/...` is the client bundle and base styles; every other
//// path is a file in the deck folder, such as theme.css and images. Deck
//// files never start with a dot, so the editor's own paths cannot hide one.

import filepath
import gleam/bit_array
import gleam/bool
import gleam/bytes_tree
import gleam/crypto
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
import junkslides/protocol.{type ServerMsg}
import junkslides/render/styles
import junkslides_server/state
import junkslides_server/store
import mist.{type Connection, type ResponseData}

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
  // `junkslides serve` says where it listens itself.
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
    [".js", "ws"] ->
      case same_origin(req, config.port) {
        True -> socket(req, owner)
        False -> refused()
      }
    // A browser takes every file as the type it is sent as, so a deck file
    // is never run as script because it looks like one.
    segments ->
      file(segments, config, owner)
      |> response.set_header("x-content-type-options", "nosniff")
  }
}

fn file(
  segments: List(String),
  config: Config,
  owner: Subject(state.Message),
) -> Response(ResponseData) {
  case segments {
    [] -> page()
    [".js", "base.css"] -> base_styles()
    [".js", "settings.css"] -> settings_styles(owner)
    [".js", "fonts", ..rest] -> serve(config.fonts, rest, Own)
    [".js", ..rest] -> serve(config.client, rest, Own)
    segments -> serve(config.folder, segments, Deck)
  }
}

/// Whose files a folder holds: the editor's own, or the deck's.
type Files {
  Own
  Deck
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

/// What the editor's page may run: the one script tag that carries this
/// response's nonce, and nothing else. An inline handler or a script that
/// reached the page with a deck's content (a drawing is inline markup, D29)
/// does not run, whatever the check on drawings let through.
pub fn page_policy(nonce: String) -> String {
  "script-src 'nonce-" <> nonce <> "'; object-src 'none'; base-uri 'none'"
}

/// A deck's own pages and drawings, opened from this server, run apart from
/// the editor: without its origin they cannot open its socket or read the
/// deck. An embedded page is framed with the same sandbox (D29).
pub const deck_policy = "sandbox allow-scripts"

/// The page: the editor's styles and the client bundle (`just client`
/// builds both into priv/static). The client links the deck's theme
/// itself, so that it can reload it.
fn page() -> Response(ResponseData) {
  let nonce =
    crypto.strong_random_bytes(16) |> bit_array.base64_url_encode(False)
  let html =
    "<!doctype html>\n<meta charset=utf-8>\n<title>junkslides</title>\n"
    <> "<link rel=stylesheet href=/.js/base.css>\n"
    <> "<link rel=stylesheet href=/.js/junkslides.css>\n<div id=app></div>\n"
    <> "<script type=module nonce="
    <> nonce
    <> " src=/.js/junkslides_client.js></script>\n"
  response.new(200)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_header("content-security-policy", page_policy(nonce))
  |> response.set_header("cache-control", "no-cache")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(html)))
}

/// The slide's base styles, shared with export.
fn base_styles() -> Response(ResponseData) {
  response.new(200)
  |> response.set_header("content-type", "text/css; charset=utf-8")
  |> response.set_body(mist.Bytes(bytes_tree.from_string(styles.base_css)))
}

/// The deck's settings from junkslides.toml, between the base styles and the theme
/// (04-layout.md, Stylesheets). The client links it with the theme.
fn settings_styles(owner: Subject(state.Message)) -> Response(ResponseData) {
  response.new(200)
  |> response.set_header("content-type", "text/css; charset=utf-8")
  |> response.set_header("cache-control", "no-cache")
  |> response.set_body(
    mist.Bytes(bytes_tree.from_string(state.settings_css(owner))),
  )
}

fn serve(
  root: String,
  segments: List(String),
  files: Files,
) -> Response(ResponseData) {
  let file = {
    use relative <- result.try(store.resolve(segments))
    let path = filepath.join(root, relative)
    mist.send_file(path, offset: 0, limit: None)
    |> result.replace_error(Nil)
    |> result.map(fn(body) { #(relative, body) })
  }
  case file {
    Ok(#(relative, body)) -> {
      let kind = content_type(relative)
      response.new(200)
      |> response.set_header("content-type", kind)
      |> response.set_header("cache-control", "no-cache")
      |> sandboxed(files, kind)
      |> response.set_body(body)
    }
    Error(Nil) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.from_string("Not found")))
  }
}

/// The deck's files that a browser opens as documents get `deck_policy`.
fn sandboxed(response: Response(a), files: Files, kind: String) -> Response(a) {
  case files, kind {
    Deck, "text/html" <> _ | Deck, "image/svg+xml" ->
      response.set_header(response, "content-security-policy", deck_policy)
    _, _ -> response
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
