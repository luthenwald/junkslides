import gleam/erlang/process
import gleam/http/request
import gleeunit
import server
import shared/msg.{Ping, Pong}
import stratus

pub fn main() -> Nil {
  gleeunit.main()
}

/// A Ping encoded with the shared codec comes back as a Pong.
pub fn round_trip_test() {
  let assert Ok(_) = server.start(4871, "../client/dist/")
  let replies = process.new_subject()
  let assert Ok(req) = request.to("http://127.0.0.1:4871/ws")
  let assert Ok(client) =
    stratus.new(request: req, state: Nil)
    |> stratus.on_message(fn(state, message, conn) {
      case message {
        stratus.Text(text) -> process.send(replies, msg.decode(text))
        stratus.User(m) -> {
          let _ = stratus.send_text_message(conn, msg.encode(m))
          Nil
        }
        _ -> Nil
      }
      stratus.continue(state)
    })
    |> stratus.start
  process.send(client.data, stratus.to_user_message(Ping(41)))
  assert process.receive(replies, 2000) == Ok(Ok(Pong(42)))
}
