//// Sends Ping(n) over a WebSocket and shows each Pong, using the codec
//// from the shared package.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_websocket as ws
import shared/msg.{Ping, Pong}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

type Model {
  Model(socket: Option(ws.WebSocket), next: Int, log: List(String))
}

type Message {
  Socket(ws.WebSocketEvent)
  SendPing
}

fn init(_flags: Nil) -> #(Model, Effect(Message)) {
  #(Model(None, 1, []), ws.init("/ws", Socket))
}

fn update(model: Model, message: Message) -> #(Model, Effect(Message)) {
  case message {
    Socket(ws.OnOpen(socket)) -> #(
      Model(..model, socket: Some(socket), log: ["open", ..model.log]),
      effect.none(),
    )
    Socket(ws.OnTextMessage(text)) -> {
      let line = case msg.decode(text) {
        Ok(Pong(n)) -> "pong " <> int.to_string(n)
        Ok(Ping(n)) -> "unexpected ping " <> int.to_string(n)
        Error(_) -> "undecodable " <> text
      }
      #(Model(..model, log: [line, ..model.log]), effect.none())
    }
    Socket(ws.OnClose(_)) -> #(
      Model(..model, socket: None, log: ["closed", ..model.log]),
      effect.none(),
    )
    Socket(_) -> #(model, effect.none())
    SendPing ->
      case model.socket {
        Some(socket) -> #(
          Model(..model, next: model.next + 1, log: [
            "ping " <> int.to_string(model.next),
            ..model.log
          ]),
          ws.send(socket, msg.encode(Ping(model.next))),
        )
        None -> #(model, effect.none())
      }
  }
}

fn view(model: Model) -> Element(Message) {
  html.main([attribute.style("font-family", "system-ui")], [
    html.button([event.on_click(SendPing), attribute.id("ping")], [
      html.text("Ping"),
    ]),
    html.ul(
      [attribute.id("log")],
      list.map(list.reverse(model.log), fn(line) {
        html.li([], [html.text(line)])
      }),
    ),
  ])
}
