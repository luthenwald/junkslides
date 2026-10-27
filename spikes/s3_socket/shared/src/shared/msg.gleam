//// A message type and its JSON codec, shared by server and client.

import gleam/dynamic/decode
import gleam/json

pub type Msg {
  Ping(n: Int)
  Pong(n: Int)
}

pub fn encode(msg: Msg) -> String {
  let #(tag, n) = case msg {
    Ping(n) -> #("ping", n)
    Pong(n) -> #("pong", n)
  }
  json.object([#("type", json.string(tag)), #("n", json.int(n))])
  |> json.to_string
}

pub fn decode(text: String) -> Result(Msg, json.DecodeError) {
  json.parse(text, decoder())
}

fn decoder() -> decode.Decoder(Msg) {
  use tag <- decode.field("type", decode.string)
  use n <- decode.field("n", decode.int)
  case tag {
    "ping" -> decode.success(Ping(n))
    "pong" -> decode.success(Pong(n))
    _ -> decode.failure(Ping(0), "Msg")
  }
}
