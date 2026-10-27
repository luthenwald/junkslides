//// The Zeno editor in the browser (05-editor.md). It is served by
//// `zeno serve` as /.zeno/zeno_client.js and mounted on `#app`.

import lustre
import zeno_client/app
import zeno_client/ui

pub fn main() -> Nil {
  let assert Ok(_) =
    lustre.application(app.init, app.update, ui.view)
    |> lustre.start("#app", Nil)
  Nil
}
