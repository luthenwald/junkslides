//// S3 in headless Chrome: the Lustre client sends Ping(1) over the
//// WebSocket and shows the server's Pong(2), both through the shared codec.

import cdp
import gleam/result
import gleam/string
import server

pub fn s3_test() {
  let assert Ok(_) = server.start(4882, "../s3_socket/client/dist/")
  let assert Ok(page) = cdp.connect(9333)
  let assert Ok(_) = cdp.open(page, "http://127.0.0.1:4882/", "#ping")
  let log = fn() { cdp.html(page, "#log") |> result.unwrap("") }
  let assert Ok(_) = cdp.wait(3000, fn() { string.contains(log(), "open") })
  let assert Ok(_) = cdp.click(page, "#ping")
  let assert Ok(_) = cdp.click(page, "#ping")
  let assert Ok(_) = cdp.wait(3000, fn() { string.contains(log(), "pong 3") })
  assert string.contains(log(), "pong 2")
}
