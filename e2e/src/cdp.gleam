//// A small Chrome DevTools Protocol client, grown from the one in
//// spikes/browser. It talks to a headless Chrome started with
//// `--remote-debugging-port` and only uses the DOM, Input, Page and
//// Emulation domains, so no JavaScript is written.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result
import gleam/string
import stratus

pub opaque type Page {
  Page(conn: Subject(stratus.InternalMessage(Call)))
}

pub opaque type Call {
  Call(method: String, params: Json, reply: Subject(Result(Dynamic, String)))
}

type State {
  State(next: Int, waiting: Dict(Int, Subject(Result(Dynamic, String))))
}

pub type Box {
  Box(x: Float, y: Float, w: Float, h: Float)
}

/// Connect to the first page target of the browser on `port`.
pub fn connect(port: Int) -> Result(Page, String) {
  let assert Ok(req) =
    request.to("http://127.0.0.1:" <> int.to_string(port) <> "/json/list")
  use resp <- result.try(
    httpc.send(req) |> result.replace_error("browser not reachable"),
  )
  let target = {
    use kind <- decode.field("type", decode.string)
    use url <- decode.field("webSocketDebuggerUrl", decode.string)
    decode.success(#(kind, url))
  }
  use targets <- result.try(
    json.parse(resp.body, decode.list(target))
    |> result.replace_error("bad target list"),
  )
  use #(_, url) <- result.try(
    list.find(targets, fn(t) { t.0 == "page" })
    |> result.replace_error("no page target"),
  )
  let assert Ok(ws) = request.to(string.replace(url, "ws://", "http://"))
  stratus.new(request: ws, state: State(1, dict.new()))
  |> stratus.on_message(on_message)
  |> stratus.start
  |> result.map(fn(started) { Page(started.data) })
  |> result.replace_error("socket failed")
}

fn on_message(state: State, message, conn) {
  case message {
    stratus.User(Call(method, params, reply)) -> {
      let text =
        json.object([
          #("id", json.int(state.next)),
          #("method", json.string(method)),
          #("params", params),
        ])
        |> json.to_string
      let _ = stratus.send_text_message(conn, text)
      stratus.continue(State(
        state.next + 1,
        dict.insert(state.waiting, state.next, reply),
      ))
    }
    stratus.Text(text) ->
      case json.parse(text, decode.at(["id"], decode.int)) {
        Ok(id) -> {
          case dict.get(state.waiting, id) {
            Ok(reply) -> process.send(reply, decode_reply(text))
            Error(_) -> Nil
          }
          stratus.continue(
            State(..state, waiting: dict.delete(state.waiting, id)),
          )
        }
        // Events carry no id; they are ignored.
        Error(_) -> stratus.continue(state)
      }
    _ -> stratus.continue(state)
  }
}

fn decode_reply(text: String) -> Result(Dynamic, String) {
  case json.parse(text, decode.at(["result"], decode.dynamic)) {
    Ok(value) -> Ok(value)
    Error(_) ->
      json.parse(text, decode.at(["error", "message"], decode.string))
      |> result.unwrap("undecodable reply")
      |> Error
  }
}

pub fn call(
  page: Page,
  method: String,
  params: List(#(String, Json)),
) -> Result(Dynamic, String) {
  process.call(page.conn, 10_000, fn(reply) {
    stratus.to_user_message(Call(method, json.object(params), reply))
  })
}

fn get(
  page: Page,
  method: String,
  params: List(#(String, Json)),
  path: List(String),
  decoder: decode.Decoder(a),
) -> Result(a, String) {
  use value <- result.try(call(page, method, params))
  decode.run(value, decode.at(path, decoder))
  |> result.replace_error(method <> ": unexpected reply")
}

pub fn viewport(page: Page, width: Int, height: Int) -> Result(Nil, String) {
  call(page, "Emulation.setDeviceMetricsOverride", [
    #("width", json.int(width)),
    #("height", json.int(height)),
    #("deviceScaleFactor", json.int(1)),
    #("mobile", json.bool(False)),
  ])
  |> result.replace(Nil)
}

/// Navigate and wait until `selector` matches.
pub fn open(page: Page, url: String, selector: String) -> Result(Nil, String) {
  use _ <- result.try(call(page, "Page.navigate", [#("url", json.string(url))]))
  wait(5000, fn() { result.is_ok(node(page, selector)) })
}

pub fn node(page: Page, selector: String) -> Result(Int, String) {
  use root <- result.try(get(
    page,
    "DOM.getDocument",
    [#("depth", json.int(0))],
    ["root", "nodeId"],
    decode.int,
  ))
  use id <- result.try(get(
    page,
    "DOM.querySelector",
    [#("nodeId", json.int(root)), #("selector", json.string(selector))],
    ["nodeId"],
    decode.int,
  ))
  case id {
    0 -> Error("no match for " <> selector)
    id -> Ok(id)
  }
}

/// How many elements match.
pub fn count(page: Page, selector: String) -> Int {
  {
    use root <- result.try(get(
      page,
      "DOM.getDocument",
      [#("depth", json.int(0))],
      ["root", "nodeId"],
      decode.int,
    ))
    get(
      page,
      "DOM.querySelectorAll",
      [#("nodeId", json.int(root)), #("selector", json.string(selector))],
      ["nodeIds"],
      decode.list(decode.int),
    )
  }
  |> result.map(list.length)
  |> result.unwrap(0)
}

pub fn attribute(
  page: Page,
  selector: String,
  name: String,
) -> Result(String, String) {
  use id <- result.try(node(page, selector))
  use flat <- result.try(get(
    page,
    "DOM.getAttributes",
    [#("nodeId", json.int(id))],
    ["attributes"],
    decode.list(decode.string),
  ))
  list.sized_chunk(flat, 2)
  |> list.find_map(fn(pair) {
    case pair {
      [key, value] if key == name -> Ok(value)
      _ -> Error(Nil)
    }
  })
  |> result.replace_error("no attribute " <> name)
}

pub fn html(page: Page, selector: String) -> Result(String, String) {
  use id <- result.try(node(page, selector))
  get(
    page,
    "DOM.getOuterHTML",
    [#("nodeId", json.int(id))],
    ["outerHTML"],
    decode.string,
  )
}

/// The border box in viewport pixels.
pub fn box(page: Page, selector: String) -> Result(Box, String) {
  use id <- result.try(node(page, selector))
  use quad <- result.try(get(
    page,
    "DOM.getBoxModel",
    [#("nodeId", json.int(id))],
    ["model", "border"],
    decode.list(number()),
  ))
  case quad {
    [x1, y1, x2, _, _, y3, ..] -> Ok(Box(x1, y1, x2 -. x1, y3 -. y1))
    _ -> Error("bad quad")
  }
}

fn number() -> decode.Decoder(Float) {
  decode.one_of(decode.float, [decode.int |> decode.map(int.to_float)])
}

pub type Mouse {
  Press
  Move
  Release
}

pub fn mouse(
  page: Page,
  kind: Mouse,
  x: Float,
  y: Float,
) -> Result(Nil, String) {
  let #(name, buttons) = case kind {
    Press -> #("mousePressed", 1)
    Move -> #("mouseMoved", 1)
    Release -> #("mouseReleased", 0)
  }
  call(page, "Input.dispatchMouseEvent", [
    #("type", json.string(name)),
    #("x", json.float(x)),
    #("y", json.float(y)),
    #("button", json.string("left")),
    #("buttons", json.int(buttons)),
    #("clickCount", json.int(1)),
  ])
  |> result.replace(Nil)
  |> result.map(fn(_) { process.sleep(frame) })
}

/// Chrome delivers input aligned to animation frames; pacing synthetic
/// events by one frame keeps them in step with the page, as a hand would.
const frame = 20

pub fn click(page: Page, selector: String) -> Result(Nil, String) {
  use b <- result.try(box(page, selector))
  let x = b.x +. b.w /. 2.0
  let y = b.y +. b.h /. 2.0
  use _ <- result.try(mouse(page, Press, x, y))
  mouse(page, Release, x, y)
}

pub fn focus(page: Page, selector: String) -> Result(Nil, String) {
  use id <- result.try(node(page, selector))
  call(page, "DOM.focus", [#("nodeId", json.int(id))]) |> result.replace(Nil)
}

pub fn type_text(page: Page, text: String) -> Result(Nil, String) {
  call(page, "Input.insertText", [#("text", json.string(text))])
  |> result.replace(Nil)
}

pub type Modifier {
  Alt
  Ctrl
  Meta
  Shift
}

/// Presses and releases one key, named by its DOM `key` value such as `j`,
/// `J`, `Enter` or `Escape`. A key without Alt, Ctrl or Meta that has text
/// also types that text, unless the page prevents it.
pub fn key(
  page: Page,
  name: String,
  modifiers: List(Modifier),
) -> Result(Nil, String) {
  let bits =
    list.fold(modifiers, 0, fn(bits, modifier) {
      bits
      + case modifier {
        Alt -> 1
        Ctrl -> 2
        Meta -> 4
        Shift -> 8
      }
    })
  let #(code, text) = case name {
    "Enter" -> #(13, "\r")
    "Escape" -> #(27, "")
    "Tab" -> #(9, "")
    "ArrowLeft" -> #(37, "")
    "ArrowUp" -> #(38, "")
    "ArrowRight" -> #(39, "")
    "ArrowDown" -> #(40, "")
    "[" -> #(219, "[")
    "]" -> #(221, "]")
    _ ->
      case string.to_utf_codepoints(string.uppercase(name)) {
        [point] -> #(string.utf_codepoint_to_int(point), name)
        _ -> #(0, "")
      }
  }
  let plain = list.all(modifiers, fn(m) { m == Shift })
  let down = case plain && text != "" {
    True -> [#("type", json.string("keyDown")), #("text", json.string(text))]
    False -> [#("type", json.string("rawKeyDown"))]
  }
  // The physical key, which pages read for Alt combinations.
  let physical = case string.length(name) {
    1 -> "Key" <> string.uppercase(name)
    _ -> name
  }
  let common = [
    #("key", json.string(name)),
    #("code", json.string(physical)),
    #("windowsVirtualKeyCode", json.int(code)),
    #("modifiers", json.int(bits)),
  ]
  use _ <- result.try(call(
    page,
    "Input.dispatchKeyEvent",
    list.append(down, common),
  ))
  use _ <- result.try(
    call(page, "Input.dispatchKeyEvent", [
      #("type", json.string("keyUp")),
      ..common
    ]),
  )
  process.sleep(frame)
  Ok(Nil)
}

/// A PNG of the viewport, for looking at the page while working on it.
pub fn screenshot(page: Page) -> Result(BitArray, String) {
  use data <- result.try(get(
    page,
    "Page.captureScreenshot",
    [#("format", json.string("png"))],
    ["data"],
    decode.string,
  ))
  bit_array.base64_decode(data) |> result.replace_error("bad image data")
}

/// Poll `check` every 20 ms until it holds or `timeout` ms pass.
pub fn wait(timeout: Int, check: fn() -> Bool) -> Result(Nil, String) {
  case check() {
    True -> Ok(Nil)
    False if timeout <= 0 -> Error("timed out")
    False -> {
      process.sleep(20)
      wait(timeout - 20, check)
    }
  }
}

pub fn round(x: Float) -> Int {
  float.round(x)
}
