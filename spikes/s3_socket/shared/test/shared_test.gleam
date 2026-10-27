import gleam/list
import gleeunit
import shared/msg.{Ping, Pong}

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn round_trip_test() {
  use m <- list.each([Ping(0), Ping(-3), Pong(42), Pong(9_007_199_254_740_991)])
  assert msg.decode(msg.encode(m)) == Ok(m)
}

pub fn wire_format_test() {
  assert msg.encode(Ping(1)) == "{\"type\":\"ping\",\"n\":1}"
  assert msg.decode("{\"type\":\"other\",\"n\":1}") != Ok(Ping(1))
}
